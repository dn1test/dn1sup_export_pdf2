// HTML5 Drag & Drop для переупорядочивания списков (стадии, строки сцен,
// карточки папок). Перетаскивание включается только после захвата «за ручку»
// или за пустое место строки (armOnControls=false), чтобы не мешать вводу.

import { ref } from 'vue'

// onDrop переименован в commitDrop: локальная function onDrop(e, index) ниже
// затеняла колбэк, drop рекурсивно вызывал сам себя и падал с TypeError.
export function useDragSort({ onDrop: commitDrop, armIgnore = 'input, select, button, label, a, textarea, [contenteditable]' }) {
  const dragArm = ref(null) // ключ строки с зажатой ручкой — включает draggable
  const dragging = ref(null) // индекс перетаскиваемой строки
  const overIdx = ref(null)
  const overPos = ref(null) // 'top' | 'bottom'

  function arm(e, key) {
    dragArm.value = e.target.closest && e.target.closest(armIgnore) ? null : key
  }

  function disarm() {
    dragArm.value = null
  }

  function onDragStart(e, index) {
    dragging.value = index
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', String(index))
  }

  function onDragOver(e, index) {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    if (dragging.value === null || dragging.value === index) return
    const rect = e.currentTarget.getBoundingClientRect()
    overIdx.value = index
    overPos.value = e.clientY - rect.top < rect.height / 2 ? 'top' : 'bottom'
  }

  function clearOver() {
    overIdx.value = null
    overPos.value = null
  }

  function clearDrag() {
    dragging.value = null
    dragArm.value = null
    clearOver()
  }

  function onDrop(e, index) {
    e.preventDefault()
    e.stopPropagation()
    if (dragging.value === null || dragging.value === index) {
      clearDrag()
      return
    }
    const rect = e.currentTarget.getBoundingClientRect()
    const isTop = e.clientY - rect.top < rect.height / 2
    let dropIndex = isTop ? index : index + 1
    if (dragging.value < dropIndex) dropIndex -= 1
    if (dropIndex !== dragging.value) commitDrop(dragging.value, dropIndex)
    clearDrag()
  }

  function rowClasses(index) {
    return {
      dragging: dragging.value === index,
      'drag-over-top': overIdx.value === index && overPos.value === 'top',
      'drag-over-bottom': overIdx.value === index && overPos.value === 'bottom',
    }
  }

  return {
    dragArm, dragging, overIdx, overPos,
    arm, disarm, onDragStart, onDragOver, clearOver, clearDrag, onDrop, rowClasses,
  }
}
