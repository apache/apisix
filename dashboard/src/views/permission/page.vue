<template>
  <div class="app-container">
    <switch-roles @change="handleRolesChange" />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import SwitchRoles from './components/SwitchRoles.vue'

@Component({
  name: 'PagePermission',
  components: {
    SwitchRoles
  }
})
export default class extends Vue {
  private handleRolesChange() {
    this.$router.push({ path: '/permission/index?' + +new Date() })
  }
}
</script>
