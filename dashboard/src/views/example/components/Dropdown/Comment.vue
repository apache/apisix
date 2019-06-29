<template>
  <el-dropdown
    :show-timeout="100"
    trigger="click"
  >
    <el-button plain>
      {{ !disableComment?'Comment: opened':'Comment: closed' }}
      <i class="el-icon-caret-bottom el-icon--right" />
    </el-button>
    <el-dropdown-menu
      slot="dropdown"
      class="no-padding"
    >
      <el-dropdown-item>
        <el-radio-group
          v-model="disableComment"
          style="padding: 10px;"
        >
          <el-radio :label="true">
            Close comment
          </el-radio>
          <el-radio :label="false">
            Open comment
          </el-radio>
        </el-radio-group>
      </el-dropdown-item>
    </el-dropdown-menu>
  </el-dropdown>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'

@Component({
  name: 'CommentDropdown'
})
export default class extends Vue {
  @Prop({ default: false }) private value!: boolean

  get disableComment() {
    return this.value
  }

  set disableComment(value) {
    this.$emit('input', value)
  }
}
</script>
