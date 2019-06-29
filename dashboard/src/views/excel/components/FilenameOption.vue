<template>
  <div style="display:inline-block;">
    <label
      class="radio-label"
      style="padding-left:0;"
    >Filename: </label>
    <el-input
      v-model="filename"
      :placeholder="$t('excel.placeholder')"
      style="width:345px;"
      prefix-icon="el-icon-document"
    />
  </div>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'

@Component({
  name: 'FilenameOption'
})
export default class extends Vue {
  @Prop({ default: '' }) private value!: string

  get filename() {
    return this.value
  }

  set filename(value) {
    this.$emit('input', value)
  }
}
</script>
