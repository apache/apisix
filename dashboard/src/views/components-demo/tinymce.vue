<template>
  <div class="components-container">
    <aside>
      {{ $t('components.tinymceTips') }}
      <a
        target="_blank"
        class="link-type"
        href="https://armour.github.io/vue-typescript-admin-docs/features/components/rich-editor.html"
      >{{ $t('components.documentation') }}</a>
    </aside>
    <div>
      <tinymce
        v-if="tinymceActive"
        v-model="content"
        :height="400"
      />
    </div>
    <!-- eslint-disable vue/no-v-html -->
    <div
      class="editor-content"
      v-html="content"
    />
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import Tinymce from '@/components/Tinymce/index.vue'

@Component({
  name: 'TinymceDemo',
  components: {
    Tinymce
  }
})
export default class extends Vue {
  private content =
    `<h1 style="text-align: center;">Welcome to the TinyMCE demo!</h1><p style="text-align: center; font-size: 15px;"><img title="Logo" src="/favicon.ico" alt="Logo" width="100" height="100" /><ul>
      <li>Our <a href="//www.tinymce.com/docs/">documentation</a> is a great resource for learning how to configure TinyMCE.</li><li>Have a specific question? Visit the <a href="https://community.tinymce.com/forum/">Community Forum</a>.</li><li>We also offer enterprise grade support as part of <a href="https://tinymce.com/pricing">TinyMCE premium subscriptions</a>.</li>
    </ul>`
  private tinymceActive = true

  deactivated() {
    this.tinymceActive = false
  }

  activated() {
    this.tinymceActive = true
  }
}
</script>

<style lang="scss" scoped>
.editor-content {
  margin-top: 20px;
}
</style>
