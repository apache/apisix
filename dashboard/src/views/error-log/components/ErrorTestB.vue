<template>
  <div>
    <!--error code-->
    {{ b = b.b }}
    <!--error code-->
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'

@Component({
  name: 'ErrorTestB'
})
export default class extends Vue {}
</script>
