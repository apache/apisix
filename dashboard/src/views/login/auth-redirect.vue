<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'

@Component({
  name: 'AuthRedirect'
})
export default class extends Vue {
  created() {
    const hash = window.location.search.slice(1)
    if (window.localStorage) {
      window.localStorage.setItem('x-admin-oauth-code', hash)
      window.close()
    }
  }

  render() {
    // Avoid warning for missing template
  }
}
</script>
