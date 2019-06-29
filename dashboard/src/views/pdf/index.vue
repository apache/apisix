<template>
  <div class="app-container">
    <aside style="margin-top:15px;">
      {{ $t('pdf.tips') }}
    </aside>
    <router-link
      target="_blank"
      to="/pdf-download-example"
    >
      <el-button type="primary">
        Click to download PDF
      </el-button>
    </router-link>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'

@Component({
  name: 'PDF'
})
export default class extends Vue {}
</script>
