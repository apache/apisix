<template>
  <div class="app-container">
    <aside>
      {{ $t('guide.description') }}
      <a
        href="https://github.com/kamranahmedse/driver.js"
        target="_blank"
      >driver.js.</a>
    </aside>
    <el-button
      icon="el-icon-question"
      type="primary"
      @click.prevent.stop="guide"
    >
      {{ $t('guide.button') }}
    </el-button>
  </div>
</template>

<script lang="ts">
import Driver from 'driver.js'
import 'driver.js/dist/driver.min.css'
import { Component, Vue } from 'vue-property-decorator'
import steps from './steps'

@Component({
  name: 'Guide'
})
export default class extends Vue {
  private driver: Driver | null = null

  mounted() {
    this.driver = new Driver()
  }

  private guide() {
    if (this.driver) {
      this.driver.defineSteps(steps)
      this.driver.start()
    }
  }
}
</script>
