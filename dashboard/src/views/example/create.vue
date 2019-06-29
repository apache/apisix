<template>
  <article-detail :is-edit="false" />
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import ArticleDetail from './components/ArticleDetail.vue'

@Component({
  name: 'CreateArticle',
  components: {
    ArticleDetail
  }
})
export default class extends Vue {}
</script>
