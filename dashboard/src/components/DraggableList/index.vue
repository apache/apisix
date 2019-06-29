<template>
  <div class="draggableList">
    <div
      :style="{width: list1width}"
      class="draggableList-list"
    >
      <h3>{{ list1Title }}</h3>
      <draggable
        :list="list1"
        group="article"
        class="dragArea"
      >
        <div
          v-for="element in list1"
          :key="element.id"
          class="list-complete-item"
        >
          <div class="list-complete-item-handle">
            {{ element.id }}[{{ element.author }}] {{ element.title }}
          </div>
          <div style="position:absolute;right:0px;">
            <span
              style="float: right ;margin-top: -20px;margin-right:5px;"
              @click="deleteEle(element)"
            >
              <i
                style="color:#ff4949"
                class="el-icon-delete"
              />
            </span>
          </div>
        </div>
      </draggable>
    </div>
    <div
      :style="{width: list2width}"
      class="draggableList-list"
    >
      <h3>{{ list2Title }}</h3>
      <draggable
        :list="list2"
        group="article"
        class="dragArea"
      >
        <div
          v-for="element in list2"
          :key="element.id"
          class="list-complete-item"
        >
          <div
            class="list-complete-item-handle2"
            @click="pushEle(element)"
          >
            {{ element.id }} [{{ element.author }}] {{ element.title }}
          </div>
        </div>
      </draggable>
    </div>
  </div>
</template>

<script lang="ts">
import Draggable from 'vuedraggable'
import { Component, Prop, Vue } from 'vue-property-decorator'
import { IArticleData } from '@/api/types'

@Component({
  name: 'DraggableList',
  components: {
    Draggable
  }
})
export default class extends Vue {
  @Prop({ default: () => [] }) private list1!: IArticleData[]
  @Prop({ default: () => [] }) private list2!: IArticleData[]
  @Prop({ default: 'list1' }) private list1Title!: string
  @Prop({ default: 'list2' }) private list2Title!: string
  @Prop({ default: '48%' }) private list1width!: string
  @Prop({ default: '48%' }) private list2width!: string

  private isNotInList1(v: IArticleData) {
    return this.list1.every(k => v.id !== k.id)
  }

  private isNotInList2(v: IArticleData) {
    return this.list2.every(k => v.id !== k.id)
  }

  private deleteEle(ele: IArticleData) {
    for (const item of this.list1) {
      if (item.id === ele.id) {
        const index = this.list1.indexOf(item)
        this.list1.splice(index, 1)
        break
      }
    }
    if (this.isNotInList2(ele)) {
      this.list2.unshift(ele)
    }
  }

  private pushEle(ele: IArticleData) {
    for (const item of this.list2) {
      if (item.id === ele.id) {
        const index = this.list2.indexOf(item)
        this.list2.splice(index, 1)
        break
      }
    }
    if (this.isNotInList1(ele)) {
      this.list1.push(ele)
    }
  }
}
</script>

<style lang="scss" scoped>
.draggableList {
  background: #fff;
  padding-bottom: 40px;

  &:after {
    content: "";
    display: table;
    clear: both;
  }

  .draggableList-list {
    float: left;
    padding-bottom: 30px;

    &:first-of-type {
      margin-right: 2%;
    }

    .dragArea {
      margin-top: 15px;
      min-height: 50px;
      padding-bottom: 30px;
    }
  }
}

.list-complete-item {
  cursor: pointer;
  position: relative;
  font-size: 14px;
  padding: 5px 12px;
  margin-top: 4px;
  border: 1px solid #bfcbd9;
  transition: all 1s;
}

.list-complete-item-handle {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-right: 50px;
}

.list-complete-item-handle2 {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-right: 20px;
}

.list-complete-item.sortable-chosen {
  background: #4AB7BD;
}

.list-complete-item.sortable-ghost {
  background: #30B08F;
}

.list-complete-enter,
.list-complete-leave-active {
  opacity: 0;
}
</style>
