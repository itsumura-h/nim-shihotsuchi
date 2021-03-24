import
  asynchttpserver, asyncdispatch, json, strformat, macros, strutils, os,
  asyncfile, mimetypes, re, tables, times
from osproc import countProcessors
import baseEnv, request, response, header, logger, error_page, resources/ddPage,
  security
export request, header


type Route* = ref object
  httpMethod*:HttpMethod
  path*:string
  action*:proc(r:Request, p:Params):Future[Response]

type MiddlewareRoute* = ref object
  httpMethods*:seq[HttpMethod]
  path*:Regex
  action*:proc(r:Request, p:Params):Future[Response]


proc params*(request:Request, route:Route):Params =
  let url = request.path
  let path = route.path
  let params = Params()
  for k, v in getUrlParams(url, path).pairs:
    params[k] = v
  for k, v in getQueryParams(request).pairs:
    params[k] = v

  if request.headers.hasKey("content-type") and request.headers["content-type"].split(";")[0] == "application/json":
    for k, v in getJsonParams(request).pairs:
      params[k] = v
  else:
    for k, v in getRequestParams(request).pairs:
      params[k] = v
  return params

proc params*(request:Request, middleware:MiddlewareRoute):Params =
  let url = request.path
  let path = middleware.path
  let params = Params()
  # for k, v in getUrlParams(url, path).pairs:
  #   params[k] = v
  for k, v in getQueryParams(request).pairs:
    params[k] = v
  for k, v in getRequestParams(request).pairs:
    params[k] = v
  return params

type Routes* = ref object
  withParams: seq[Route]
  withoutParams: OrderedTable[string, Route]
  middlewares: seq[MiddlewareRoute]

func newRoutes*():Routes =
  return Routes()

func newRoute(httpMethod:HttpMethod, path:string, action:proc(r:Request, p:Params):Future[Response]):Route =
  return Route(
    httpMethod:httpMethod,
    path:path,
    action:action
  )

func add*(self:var Routes, httpMethod:HttpMethod, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  let route = newRoute(httpMethod, path, action)
  if path.contains("{"):
    self.withParams.add(route)
  else:
    self.withoutParams[ $httpMethod & ":" & path ] = route
    if not [HttpGet, HttpHead, HttpPost].contains(httpMethod):
      self.withoutParams[ $(HttpOptions) & ":" & path ] = route

func middleware*(
  self:var Routes,
  path:Regex,
  action:proc(r:Request, p:Params):Future[Response]
) =
  self.middlewares.add(
    MiddlewareRoute(
      httpMethods: newSeq[HttpMethod](),
      path: path,
      action: action
    )
  )

func middleware*(
  self:var Routes,
  httpMethods:seq[HttpMethod],
  path:Regex,
  action:proc(r:Request, p:Params):Future[Response]
) =
  self.middlewares.add(
    MiddlewareRoute(
      httpMethods: httpMethods,
      path: path,
      action: action
    )
  )

func get*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpGet, path, action)

func post*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpPost, path, action)

func put*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpPut, path, action)

func patch*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpPatch, path, action)

func delete*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpDelete, path, action)

func head*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpHead, path, action)

func options*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpOptions, path, action)

func trace*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpTrace, path, action)

func connect*(self:var Routes, path:string, action:proc(r:Request, p:Params):Future[Response]) =
  add(self, HttpConnect, path, action)

macro groups*(head, body:untyped):untyped =
  var newNode = ""
  for row in body:
    let rowNode = fmt"""
{row[0].repr}("{head}{row[1]}", {row[2].repr})
"""
    newNode.add(rowNode)
  return parseStmt(newNode)

const errorStatusArray* = [505, 504, 503, 502, 501, 500, 451, 431, 429, 428, 426,
  422, 421, 418, 417, 416, 415, 414, 413, 412, 411, 410, 409, 408, 407, 406,
  405, 404, 403, 401, 400, 307, 305, 304, 303, 302, 301, 300]

macro createHttpCodeError():untyped =
  var strBody = ""
  for num in errorStatusArray:
    strBody.add(fmt"""
of "Error{num.repr}":
  return Http{num.repr}
""")
  return parseStmt(fmt"""
case $exception.name
{strBody}
else:
  return Http400
""")

func checkHttpCode(exception:ref Exception):HttpCode =
  ## Generated by macro createHttpCodeError.
  ## List is httpCodeArray
  ## .. code-block:: nim
  ##   case $exception.name
  ##   of Error505:
  ##     return Http505
  ##   of Error504:
  ##     return Http504
  ##   of Error503:
  ##     return Http503
  ##   .
  ##   .
  createHttpCodeError


proc runMiddleware(req:Request, routes:Routes, headers:HttpHeaders):Future[Response] {.async, gcsafe.} =
  var
    response = Response()
    headers = if not headers.isNil: headers else: newHttpHeaders()
    status = HttpCode(0)
  for route in routes.middlewares:
    if route.httpMethods.len > 0:
      if findAll(req.path, route.path).len > 0 and route.httpMethods.contains(req.httpMethod):
        let params = req.params(route)
        response = await route.action(req, params)
    else:
      if findAll(req.path, route.path).len > 0:
        let params = req.params(route)
        response = await route.action(req, params)
    if not response.headers.isNil and response.headers.len > 0:
      headers = response.headers & headers
    if response.status != HttpCode(0):
      status = response.status
  response.headers = headers
  response.status = status
  return response

proc runController(req:Request, route:Route, headers: HttpHeaders):Future[Response] {.async, gcsafe.} =
  var response: Response
  let params = req.params(route)
  response = await route.action(req, params)
  response.headers = response.headers & headers
  echoLog($response.status & "  " & req.hostname & "  " & $req.httpMethod & "  " & req.path)
  return response

func doesRunAnonymousLogin(req:Request, res:Response):bool =
  if res.isNil:
    return false
  if not ENABLE_ANONYMOUS_COOKIE:
    return false
  if req.httpMethod == HttpOptions:
    return false
  if res.headers.hasKey("set-cookie"):
    return false
  # if not req.headers.hasKey("content-type"):
  #   return false
  # if req.headers["content-type"].split(";")[0] == "application/json":
  #   return false
  return true

proc serveCore(params:(Routes, int)){.thread.} =
  let (routes, port) = params
  var server = newAsyncHttpServer(true, true)

  proc cb(req: Request) {.async, gcsafe.} =
    var
      headers = newHttpHeaders()
      response: Response
    # static file response
    if req.path.contains("."):
      let filepath = getCurrentDir() & "/public" & req.path
      if fileExists(filepath):
        let file = openAsync(filepath, fmRead)
        let data = await file.readAll()
        let contentType = newMimetypes().getMimetype(req.path.split(".")[^1])
        headers["content-type"] = contentType
        response = Response(status:Http200, body:data, headers:headers)
    else:
      # check path match with controller routing → run middleware → run controller
      try:
        let key = $(req.httpMethod) & ":" & req.path
        if req.httpMethod == HttpOptions:
          response = await runMiddleware(req, routes, headers)
        elif routes.withoutParams.hasKey(key):
          response = await runMiddleware(req, routes, headers)
          let route = routes.withoutParams[key]
          headers = headers & response.headers
          response = await runController(req, route, headers)
        else:
          for route in routes.withParams:
            if route.httpMethod == req.httpMethod and isMatchUrl(req.path, route.path):
              response = await runMiddleware(req, routes, headers)
              if req.httpMethod != HttpOptions:
                headers = headers & response.headers
                response = await runController(req, route, headers)
                break
      except:
        headers["content-type"] = "text/html; charset=utf-8"
        let exception = getCurrentException()
        if exception.name == "DD".cstring:
          var msg = exception.msg
          msg = msg.replace(re"Async traceback:[.\s\S]*")
          response = Response(status:Http200, body:ddPage(msg), headers:headers)
        elif exception.name == "ErrorAuthRedirect".cstring:
          headers["location"] = exception.msg
          headers["set-cookie"] = "session_id=; expires=31-Dec-1999 23:59:59 GMT" # Delete session id
          response = Response(status:Http302, body:"", headers:headers)
        elif exception.name == "ErrorRedirect".cstring:
          headers["location"] = exception.msg
          response = Response(status:Http302, body:"", headers:headers)
        else:
          let status = checkHttpCode(exception)
          response = Response(status:status, body:errorPage(status, exception.msg), headers:headers)
          echoErrorMsg($response.status & "  " & req.hostname & "  " & $req.httpMethod & "  " & req.path)
          echoErrorMsg(exception.msg)

      # anonymous user login should run only for response from controler
      if doesRunAnonymousLogin(req, response):
        let auth = await newAuth(req)
        if await anonumousCreateSession(auth, req):
          # create new session
          response = await response.setAuth(auth)
        else:
          # keep session id from request and update expire
          var cookie = newCookie(req)
          cookie.updateExpire(SESSION_TIME, Minutes)
          response = response.setCookie(cookie)

    if response.isNil:
      headers["content-type"] = "text/html; charset=utf-8"
      response = Response(status:Http404, body:errorPage(Http404, ""), headers:headers)
      echoErrorMsg($response.status & "  " & req.hostname & "  " & $req.httpMethod & "  " & req.path)

    response.headers.setDefaultHeaders()

    await req.respond(response.status, response.body, response.headers.format())
    # keep-alive
    req.dealKeepAlive()
  waitFor server.serve(Port(port), cb)

proc serve*(routes: var Routes) =
  let port = PORT_NUM
  let numThreads =
    when compileOption("threads"):
      countProcessors()
    else:
      1

  if numThreads == 1:
    echo("Starting 1 thread")
  else:
    echo("Starting ", numThreads, " threads")
  echo("Listening on port ", port)
  when compileOption("threads"):
    var threads = newSeq[Thread[(Routes, int)]](numThreads)
    for i in 0 ..< numThreads:
      createThread(
        threads[i], serveCore, (routes, port)
      )
    joinThreads(threads)
  else:
    serveCore((routes, port))
