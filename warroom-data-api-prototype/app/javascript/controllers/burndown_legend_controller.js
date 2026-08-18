import { Controller } from "@hotwired/stimulus"

// 點圖例可以切換顯示/隱藏該人的長條與折線，方便在多人協作的議題中專注比對單一人的資料，
// 不用被其他人的線條/長條干擾視線。純前端顯示切換（class + opacity），不影響底層資料、
// 燈號或右軸刻度的計算。
export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget
    const assignee = button.dataset.assignee
    const hidden = button.classList.toggle("is-hidden")

    this.element.querySelectorAll(`[data-assignee="${CSS.escape(assignee)}"]`).forEach((el) => {
      if (el === button) return

      el.classList.toggle("is-dimmed", hidden)
    })
  }
}
