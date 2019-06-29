<template>
  <div class="components-container">
    <aside>
      draggable-list base on
      <a
        href="https://github.com/SortableJS/Vue.Draggable"
        target="_blank"
      >Vue.Draggable</a>
    </aside>
    <div class="editor-container">
      <draggable-list
        :list1="list1"
        :list2="list2"
        list1-title="List"
        list2-title="Article pool"
      />
    </div>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import { getArticles } from '@/api/articles'
import DraggableList from '@/components/DraggableList/index.vue'

@Component({
  name: 'DraggableListDemo',
  components: {
    DraggableList
  }
})
export default class extends Vue {
  private list1 = []
  private list2 = []

  created() {
    this.fetchData()
  }

  private async fetchData() {
    const { data } = await getArticles({ /* Your params here */ })
    this.list1 = data.items.splice(0, 5)
    this.list2 = data.items
  }
}
</script>
