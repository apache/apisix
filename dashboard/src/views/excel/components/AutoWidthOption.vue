<template>
  <div style="display:inline-block;">
    <label class="radio-label">Cell Auto-Width: </label>
    <el-radio-group v-model="autoWidth">
      <el-radio
        :label="true"
        border
      >
        True
      </el-radio>
      <el-radio
        :label="false"
        border
      >
        False
      </el-radio>
    </el-radio-group>
  </div>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'

@Component({
  name: 'AutoWidthOption'
})
export default class extends Vue {
  @Prop({ default: true }) private value!: boolean

  get autoWidth() {
    return this.value
  }

  set autoWidth(value) {
    this.$emit('input', value)
  }
}
</script>
