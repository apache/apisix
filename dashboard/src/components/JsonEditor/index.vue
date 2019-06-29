<template>
  <div class="json-editor">
    <textarea ref="textarea" />
  </div>
</template>

<script lang="ts">
import CodeMirror, { Editor } from 'codemirror'
import 'codemirror/addon/lint/lint.css'
import 'codemirror/lib/codemirror.css'
import 'codemirror/theme/rubyblue.css'
import 'codemirror/mode/javascript/javascript'
import 'codemirror/addon/lint/lint'
import 'codemirror/addon/lint/json-lint'
import { Component, Prop, Vue, Watch } from 'vue-property-decorator'

// HACK: have to use script-loader to load jsonlint
/* eslint-disable import/no-webpack-loader-syntax */
require('script-loader!jsonlint')

@Component({
  name: 'JsonEditor'
})
export default class extends Vue {
  @Prop({ required: true }) private value!: string

  private jsonEditor?: Editor

  @Watch('value')
  private onValueChange(value: string) {
    if (this.jsonEditor) {
      const editorValue = this.jsonEditor.getValue()
      if (value !== editorValue) {
        this.jsonEditor.setValue(JSON.stringify(this.value, null, 2))
      }
    }
  }

  mounted() {
    this.jsonEditor = CodeMirror.fromTextArea(this.$refs.textarea as HTMLTextAreaElement, {
      lineNumbers: true,
      mode: 'application/json',
      gutters: ['CodeMirror-lint-markers'],
      theme: 'rubyblue',
      lint: true
    })

    this.jsonEditor.setValue(JSON.stringify(this.value, null, 2))
    this.jsonEditor.on('change', editor => {
      this.$emit('changed', editor.getValue())
      this.$emit('input', editor.getValue())
    })
  }

  public setValue(value: string) {
    if (this.jsonEditor) {
      this.jsonEditor.setValue(value)
    }
  }

  public getValue() {
    if (this.jsonEditor) {
      return this.jsonEditor.getValue()
    }
    return ''
  }
}
</script>

<style lang="scss">
.CodeMirror {
  height: auto;
  min-height: 300px;
  font-family: inherit;
}

.CodeMirror-scroll {
  min-height: 300px;
}

.cm span.cm-string {
  color: #F08047;
}
</style>

<style lang="scss" scoped>
.json-editor {
  height: 100%;
  position: relative;
}
</style>
