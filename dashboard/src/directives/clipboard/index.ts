// Inspired by https://github.com/Inndy/vue-clipboard2
import Clipboard from 'clipboard'
import { DirectiveOptions } from 'vue'
import { DirectiveBinding } from 'vue/types/options'

if (!Clipboard) {
  throw new Error('you should npm install `clipboard` --save at first ')
}

let successCallback: Function
let errorCallback: Function
let clipboardInstance: Clipboard

const updateClipboard = (el: HTMLElement, binding: DirectiveBinding) => {
  if (binding.arg === 'success') {
    successCallback = binding.value
  } else if (binding.arg === 'error') {
    errorCallback = binding.value
  } else {
    clipboardInstance = new Clipboard(el, {
      text() { return binding.value },
      action() { return binding.arg === 'cut' ? 'cut' : 'copy' }
    })
    clipboardInstance.on('success', e => {
      const callback = successCallback
      callback && callback(e)
    })
    clipboardInstance.on('error', e => {
      const callback = errorCallback
      callback && callback(e)
    })
  }
}

export const clipboard: DirectiveOptions = {
  bind(el, binding) {
    updateClipboard(el, binding)
  },

  update(el, binding) {
    updateClipboard(el, binding)
  },

  unbind(el, binding) {
    if (binding.arg === 'success') {
      // ...
    } else if (binding.arg === 'error') {
      // ...
    } else {
      clipboardInstance.destroy()
    }
  }
}
