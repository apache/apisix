<template>
  <div class="chart-container">
    <bar-chart
      height="100%"
      width="100%"
    />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import BarChart from '@/components/Charts/BarChart.vue'

@Component({
  name: 'BarChartDemo',
  components: {
    BarChart
  }
})
export default class extends Vue {}
</script>

<style lang="scss" scoped>
.chart-container {
  position: relative;
  width: 100%;
  height: calc(100vh - 84px);
}
</style>
