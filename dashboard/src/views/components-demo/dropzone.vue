<template>
  <div class="components-container">
    <aside>
      Based on
      <a
        class="link-type"
        href="https://github.com/rowanwins/vue-dropzone"
      >vue-dropzone</a>.
    </aside>
    <div class="editor-container">
      <dropzone
        id="myVueDropzone"
        url="https://httpbin.org/post"
        @dropzone-success="dropzoneSuccess"
        @dropzone-removed-file="dropzoneRemovedFile"
      />
    </div>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import Dropzone from '@/components/Dropzone/index.vue'

@Component({
  name: 'DropzoneDemo',
  components: {
    Dropzone
  }
})
export default class extends Vue {
  private dropzoneSuccess(file: File, response: any) {
    this.$message({ message: 'Upload success', type: 'success' })
  }

  private dropzoneRemovedFile(file: File, error: Error, xhr: XMLHttpRequest) {
    this.$message({ message: 'Delete success', type: 'success' })
  }
}
</script>
