<template>
  <div class="chart-container">
    <line-chart
      height="100%"
      width="100%"
    />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import LineChart from '@/components/Charts/LineChart.vue'

@Component({
  name: 'LineChartDemo',
  components: {
    LineChart
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
