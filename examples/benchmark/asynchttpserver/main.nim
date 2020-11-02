import random, json
import asynchttpserver, asyncdispatch
import allographer/query_builder
randomize()
const range1_10000 = 1..10000

proc serve(port:int) =
  block:
    var server = newAsyncHttpServer(true, true)
    proc cb(req: Request) {.async, gcsafe.} =
      var countNum = 500

      var response = newSeq[JsonNode](countNum)
      var getFutures = newSeq[Future[Row]](countNum)
      var updateFutures = newSeq[Future[void]](countNum)
      for i in 1..countNum:
        let index = rand(range1_10000)
        let number = rand(range1_10000)
        getFutures[i-1] = rdb().table("World").select("id", "randomNumber").asyncFindPlain(index)
        updateFutures[i-1] = rdb()
                            .table("World")
                            .where("id", "=", index)
                            .asyncUpdate(%*{"randomNumber": number})
        response[i-1] = %*{"id":index, "randomNumber": number}

      try:
        discard await all(getFutures)
        await all(updateFutures)
      except:
        discard
      await req.respond(Http200, $response)
      # await req.respond(Http200, "Hello World")
    waitFor server.serve(Port(port), cb)

serve(5000)
