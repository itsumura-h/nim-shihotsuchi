from strutils import join
import asyncdispatch
import ../../../../../../src/basolato/middleware


proc corsHeader*(): Headers =
  let allowedMethods = [
    "OPTIONS",
    "GET",
    "POST",
    "PUT",
    "DELETE"
  ]

  let allowedHeaders = [
    "content-type",
  ]

  return {
    "Cache-Control": "no-cache",
    "Access-Control-Allow-Origin": "http://localhost:3000",
    "Access-Control-Allow-Methods": allowedMethods.join(", "),
    "Access-Control-Allow-Headers": allowedHeaders.join(", "),
    "Access-Control-Allow-Credentials": "true",
    "Access-Control-Expose-Headers": allowedHeaders.join(", "),
  }.toHeaders()


proc secureHeader*(): Headers =
  return {
    "Strict-Transport-Security": ["max-age=63072000", "includeSubdomains"].join(", "),
    "X-Frame-Options": "SAMEORIGIN",
    "X-XSS-Protection": ["1", "mode=block"].join(", "),
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": ["no-referrer", "strict-origin-when-cross-origin"].join(", "),
    "Cache-control": ["no-cache", "no-store", "must-revalidate"].join(", "),
    "Pragma": "no-cache",
  }.toHeaders()

proc setCorsHeadersMiddleware*(r:Request, p:Params):Future[Response] {.async.} =
  let headers = corsHeader() & secureHeader()
  return next(status=Http204, headers=headers)