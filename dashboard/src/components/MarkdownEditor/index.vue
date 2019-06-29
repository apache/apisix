<template>
  <div :id="id" />
</template>

<script lang="ts">
import 'codemirror/lib/codemirror.css' // codemirror
import 'tui-editor/dist/tui-editor.css' // editor ui
import 'tui-editor/dist/tui-editor-contents.css' // editor content
import { Component, Prop, Vue, Watch } from 'vue-property-decorator'
import defaultOptions from './default-options'
import TuiEditor from 'tui-editor'

const defaultId = () => 'markdown-editor-' + +new Date() + ((Math.random() * 1000).toFixed(0) + '')

@Component({
  name: 'MarkdownEditor'
})
export default class extends Vue {
  @Prop({ required: true }) private value!: string
  @Prop({ default: defaultId }) private id!: string
  @Prop({ default: () => defaultOptions }) private options!: tuiEditor.IEditorOptions
  @Prop({ default: 'markdown' }) private mode!: string
  @Prop({ default: '300px' }) private height!: string
  // https://github.com/nhnent/tui.editor/tree/master/src/js/langs
  @Prop({ default: 'en_US' }) private language!: string

  private markdownEditor?: tuiEditor.Editor

  get editorOptions() {
    const options = Object.assign({}, defaultOptions, this.options)
    options.initialEditType = this.mode
    options.height = this.height
    options.language = this.language
    return options
  }

  @Watch('value')
  private onValueChange(value: string, oldValue: string) {
    if (this.markdownEditor) {
      if (value !== oldValue && value !== this.markdownEditor.getValue()) {
        this.markdownEditor.setValue(value)
      }
    }
  }

  @Watch('language')
  private onLanguageChange() {
    this.destroyEditor()
    this.initEditor()
  }

  @Watch('height')
  private onHeightChange(value: string) {
    if (this.markdownEditor) {
      this.markdownEditor.height(value)
    }
  }

  @Watch('mode')
  private onModeChange(value: string) {
    if (this.markdownEditor) {
      this.markdownEditor.changeMode(value)
    }
  }

  mounted() {
    this.initEditor()
  }

  destroyed() {
    this.destroyEditor()
  }

  private initEditor() {
    const editorElement = document.getElementById(this.id)
    if (!editorElement) return
    this.markdownEditor = new TuiEditor({
      el: editorElement,
      ...this.editorOptions
    })
    if (this.value) {
      this.markdownEditor.setValue(this.value)
    }
    this.markdownEditor.on('change', () => {
      this.$emit('input', this.markdownEditor!.getValue())
    })
  }

  private destroyEditor() {
    if (!this.markdownEditor) return
    this.markdownEditor.off('change')
    this.markdownEditor.remove()
    this.markdownEditor = undefined
  }

  public focus() {
    if (this.markdownEditor) {
      this.markdownEditor.focus()
    }
  }

  public setValue(value: string) {
    if (this.markdownEditor) {
      this.markdownEditor.setValue(value)
    }
  }

  public getValue() {
    if (this.markdownEditor) {
      return this.markdownEditor.getValue()
    }
    return ''
  }

  public setHtml(value: string) {
    if (this.markdownEditor) {
      this.markdownEditor.setHtml(value)
    }
  }

  public getHtml() {
    if (this.markdownEditor) {
      return this.markdownEditor.getHtml()
    }
    return ''
  }
}
</script>
