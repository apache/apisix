<template>
  <div class="app-container">
    <el-tabs v-model="activeName">
      <el-tab-pane
        label="use clipboard directly"
        name="directly"
      >
        <el-input
          v-model="inputData"
          placeholder="Please input"
          style="width:400px; max-width:100%;"
        />
        <el-button
          type="primary"
          icon="document"
          @click="handleClipboard(inputData, $event)"
        >
          copy
        </el-button>
      </el-tab-pane>
      <el-tab-pane
        label="use clipboard by v-directive"
        name="v-directive"
      >
        <el-input
          v-model="inputData"
          placeholder="Please input"
          style="width:400px; max-width:100%;"
        />
        <el-button
          v-clipboard:copy="inputData"
          v-clipboard:success="clipboardSuccess"
          type="primary"
          icon="document"
        >
          copy
        </el-button>
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import { handleClipboard, clipboardSuccess } from '@/utils/clipboard' // use clipboard directly

@Component({
  name: 'Clipboard'
})
export default class extends Vue {
  private activeName = 'directly'
  private inputData = 'https://github.com/Armour/vue-typescript-admin-template'
  private clipboardSuccess = clipboardSuccess
  private handleClipboard = handleClipboard
}
</script>
