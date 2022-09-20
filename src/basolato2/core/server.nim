import
  std/asyncdispatch,
  std/asyncfile,
  std/httpcore,
  std/options,
  std/os,
  std/re,
  std/strutils,
  std/strformat,
  std/tables,
  std/times,
  std/mimetypes,
  ./baseEnv,
  ./security/context,
  ./security/cookie,
  ./route,
  ./request,
  ./header,
  ./response,
  ./logger,
  ./resources/dd_page,
  ./resources/error_page
from ./httpbeast/httpbeast import send, initSettings, run


proc serve*(seqRoutes:seq[Routes], port=5000) =
  var routes =  Routes.new()
  for tmpRoutes in seqRoutes:
    routes.withParams.add(tmpRoutes.withParams)
    for path, route in tmpRoutes.withoutParams:
      routes.withoutParams[path] = route
  
  proc cd(req:Request):Future[void] {.async.}=
    var
      headers = newHttpHeaders(true)
      response = Response(status:HttpCode(0), headers:newHttpHeaders(true))
      context = Context.new(req, ENABLE_ANONYMOUS_COOKIE).await
      httpMethodStr = ""

    try:
      httpMethodStr = $req.httpMethod()
      # static file response
      if req.path.contains("."):
        let filepath = getCurrentDir() & "/public" & req.path
        if fileExists(filepath):
          let file = openAsync(filepath, fmRead)
          let data = file.readAll().await
          let contentType = newMimetypes().getMimetype(req.path.split(".")[^1])
          headers["Content-Type"] = contentType
          response = Response(status:Http200, body:data, headers:headers)
      else:
        # check path match with controller routing → run middleware → run controller
        let httpMethod =
          if req.httpMethod == HttpHead:
            HttpGet
          else:
            req.httpMethod
        let key = $(httpMethod) & ":" & req.path

        # withoutParams
        if routes.withoutParams.hasKey(key):
          let route = routes.withoutParams[key]
          response = await createResponse(req, route, httpMethod, headers, context)
        # withParams
        else:
          for route in routes.withParams:
            if route.httpMethod == httpMethod and isMatchUrl(req.path, route.path):
              response = await createResponse(req, route, httpMethod, headers, context)
              break
        if req.httpMethod == HttpHead:
          response.body = ""

         # anonymous user login should run only for response from controler
        if doesRunAnonymousLogin(req, response) and context.isValid().await:
          # keep session id from request and update expire
          var cookies = Cookies.new(req)
          let sessionId = await context.getToken()
          cookies.set("session_id", sessionId, expire=timeForward(SESSION_TIME, Minutes))
          response = response.setCookie(cookies)
    except:
      headers["Content-Type"] = "text/html; charset=utf-8"
      let exception = getCurrentException()
      if exception.name == "DD".cstring:
        var msg = exception.msg
        msg = msg.replace(re"Async traceback:[.\s\S]*")
        response = Response(status:Http200, body:ddPage(msg), headers:headers)
      elif exception.name == "ErrorAuthRedirect".cstring:
        headers["Location"] = exception.msg
        headers["set-cookie"] = "session_id=; expires=31-Dec-1999 23:59:59 GMT" # Delete session id
        response = Response(status:Http302, body:"", headers:headers)
      elif exception.name == "ErrorRedirect".cstring:
        headers["Location"] = exception.msg
        response = Response(status:Http302, body:"", headers:headers)
      elif exception.name == "ErrorHttpParse".cstring:
        response = Response(status:Http501, body:"", headers:headers)
      else:
        let status = checkHttpCode(exception)
        response = Response(status:status, body:errorPage(status, exception.msg), headers:headers)
        echoErrorMsg(&"{$response.status}  {req.hostname()}  {httpMethodStr}  {req.path}")
        echoErrorMsg(exception.msg)


    if response.status == HttpCode(0):
      headers["Content-Type"] = "text/html; charset=utf-8"
      response = Response(status:Http404, body:errorPage(Http404, ""), headers:headers)
      echoErrorMsg(&"{$response.status}  {req.hostname()}  {httpMethodStr}  {req.path}")

    response.headers.setDefaultHeaders()
    req.send(response.status, response.body, response.headers.format())
    # keep-alive
    # req.dealKeepAlive()

  
  let settings = initSettings(port=Port(port))
  run(cd, settings)
