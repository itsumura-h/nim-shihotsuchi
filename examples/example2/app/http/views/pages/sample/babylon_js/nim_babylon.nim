import
  std/asyncjs,
  std/jscore,
  std/jsfetch,
  std/jsffi,
  std/math
from std/sugar import `=>`

let
  module {.importc.}: JsObject
  document {.importc.}: JsObject
  console {.importc.}: JsObject
  BABYLON {.importc.}: JsObject


proc main*() {.exportc.} =
  let canvas = document.getElementById("renderCanvas")
  let engine = jsNew BABYLON.Engine(canvas)

  # ここから
  proc createScene(canvas, engine:JsObject):JsObject =
    # シーンを作成
    let scene = jsNew BABYLON.Scene(engine)
    # カメラを作成
    let camera = jsNew BABYLON.ArcRotateCamera(
      "camera",
      -(PI / 2),
      PI / 2.5,
      3,
      jsNew BABYLON.Vector3(0, 0, 0),
      scene
    )
    # カメラがユーザからの入力で動くように
    camera.attachControl(canvas, true)
    # ライトを作成
    let light = jsNew BABYLON.HemisphericLight("light", jsNew BABYLON.Vector3(0, 1, 0), scene)
    # 箱 (豆腐) を作成
    let box = jsNew BABYLON.MeshBuilder.CreateBox("box", newJsObject(), scene)
    return scene
 
  let scene = createScene(canvas, engine)
  engine.runRenderLoop((
    proc() =
      scene.render()
  ))


#[

function main() {
  const canvas = document.getElementById('renderCanvas');
  const engine = new BABYLON.Engine(canvas);
  // ここから
  function createScene() {
    // シーンを作成
    const scene = new BABYLON.Scene(engine);
    // カメラを作成
    const camera = new BABYLON.ArcRotateCamera("camera", -Math.PI / 2, Math.PI / 2.5, 3, new BABYLON.Vector3(0, 0, 0), scene);
    // カメラがユーザからの入力で動くように
    camera.attachControl(canvas, true);
    // ライトを作成
    const light = new BABYLON.HemisphericLight("light", new BABYLON.Vector3(0, 1, 0), scene);
    // 箱 (豆腐) を作成
    const box = BABYLON.MeshBuilder.CreateBox("box", {}, scene);
    return scene;
  }
  
  const scene = createScene();
  
  engine.runRenderLoop(() => {
    scene.render();
  });
  
  window.addEventListener('resize', () => {
    engine.resize();
  });
}
window.addEventListener('DOMContentLoaded', main);

]#