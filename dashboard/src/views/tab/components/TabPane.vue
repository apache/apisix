<template>
  <el-table
    :data="list"
    border
    fit
    highlight-current-row
    style="width: 100%"
  >
    <el-table-column
      v-loading="loading"
      align="center"
      label="ID"
      width="65"
      element-loading-text="请给我点时间！"
    >
      <template slot-scope="scope">
        <span>{{ scope.row.id }}</span>
      </template>
    </el-table-column>

    <el-table-column
      width="180px"
      align="center"
      label="Date"
    >
      <template slot-scope="scope">
        <span>{{ scope.row.timestamp | parseTime }}</span>
      </template>
    </el-table-column>

    <el-table-column
      min-width="240px"
      label="Title"
    >
      <template slot-scope="{row}">
        <span>{{ row.title }}</span>
        <el-tag>{{ row.type }}</el-tag>
      </template>
    </el-table-column>

    <el-table-column
      width="180px"
      align="center"
      label="Author"
    >
      <template slot-scope="scope">
        <span>{{ scope.row.author }}</span>
      </template>
    </el-table-column>

    <el-table-column
      width="120px"
      label="Importance"
    >
      <template slot-scope="scope">
        <svg-icon
          v-for="n in +scope.row.importance"
          :key="n"
          name="star"
        />
      </template>
    </el-table-column>

    <el-table-column
      align="center"
      label="Readings"
      width="95"
    >
      <template slot-scope="scope">
        <span>{{ scope.row.pageviews }}</span>
      </template>
    </el-table-column>

    <el-table-column
      class-name="status-col"
      label="Status"
      width="110"
    >
      <template slot-scope="{row}">
        <el-tag :type="row.status | articleStatusFilter">
          {{ row.status }}
        </el-tag>
      </template>
    </el-table-column>
  </el-table>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'
import { getArticles } from '@/api/articles'

@Component({
  name: 'TabPane'
})
export default class extends Vue {
  @Prop({ default: 'CN' }) private type!: string

  private list = null
  private listQuery = {
    page: 1,
    limit: 5,
    type: this.type,
    sort: 'id'
  }
  private loading = false

  created() {
    this.getList()
  }

  private async getList() {
    this.loading = true
    this.$emit('create') // for test
    const { data } = await getArticles(this.listQuery)
    this.list = data.items
    // Just to simulate the time of the request
    setTimeout(() => {
      this.loading = false
    }, 0.5 * 1000)
  }
}
</script>
