import { App } from "./app.js"
import { createRoot } from "react-dom/client"

const root = document.getElementById("root")

if (!root) {
  throw new Error("No se encontro el nodo root")
}

createRoot(root).render(<App />)
