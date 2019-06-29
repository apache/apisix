<template>
  <div style="padding:30px;">
    <el-alert
      :closable="false"
      title="menu 1-2-2"
      type="warning"
    />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'

@Component({
  name: 'Menu1-2-2'
})
export default class extends Vue {}
</script>
