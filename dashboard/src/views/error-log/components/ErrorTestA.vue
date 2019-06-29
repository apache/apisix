<template>
  <div>
    <!--error code-->
    {{ a.a }}
    <!--error code-->
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'

@Component({
  name: 'ErrorTestA'
})
export default class extends Vue {}
</script>
