<template>
  <div class="app-container">
    <div style="margin:0 0 5px 20px">
      {{ $t('table.dynamicTips1') }}
    </div>
    <fixed-header-table />

    <div style="margin:30px 0 5px 20px">
      {{ $t('table.dynamicTips2') }}
    </div>
    <unfixed-header-table />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import FixedHeaderTable from './components/FixedHeaderTable.vue'
import UnfixedHeaderTable from './components/UnfixedHeaderTable.vue'

@Component({
  name: 'DynamicTable',
  components: {
    FixedHeaderTable,
    UnfixedHeaderTable
  }
})
export default class extends Vue {}
</script>
