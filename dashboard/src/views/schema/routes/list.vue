<template>
  <div class="app-container">
    <div class="filter-container">
      <el-button
        class="filter-item"
        style="margin-left: 10px;"
        type="primary"
        icon="el-icon-edit"
        @click="handleCreate"
      >
        {{ $t('table.add') }}
      </el-button>
    </div>

    <el-table
      :key="tableKey"
      v-loading="listLoading"
      :data="tableData"
      border
      fit
      highlight-current-row
      style="width: 100%;"
      @sort-change="sortChange"
    >
      <el-table-column
        v-for="(item, index) of tableKeys"
        :key="index"
        :label="item"
        :prop="item"
        width="400"
        class-name="status-col"
      />
      <el-table-column
        :label="$t('table.actions')"
        align="center"
        width="230"
        class-name="fixed-width"
      >
        <template slot-scope="{row}">
          <el-button
            type="primary"
            size="mini"
            @click="handleToEdit(row)"
          >
            {{ $t('table.edit') }}
          </el-button>

          <el-button
            v-if="row.status!=='deleted'"
            size="mini"
            type="danger"
            @click="handleRemove(row)"
          >
            {{ $t('table.delete') }}
          </el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import { Form } from 'element-ui'
import { getArticles, getPageviews, createArticle, updateArticle, defaultArticleData } from '../../../api/articles'
import { IArticleData, IConsumerData, IDataWrapper } from '../../../api/types'
import { exportJson2Excel } from '../../../utils/excel'
import { formatJson } from '../../../utils'
import Pagination from '../../../components/Pagination/index.vue'

import { getList, removeRouter } from '../../../api/schema/routes'

@Component({
  name: 'RoutesList',
  components: {
    Pagination
  }
})
export default class extends Vue {
  private tableKey = 0
  private list: IArticleData[] = []
  private total = 0
  private listLoading = true
  private listQuery = {
    page: 1,
    limit: 20,
    importance: undefined,
    title: undefined,
    type: undefined,
    sort: '+id'
  }

  private tableData: IConsumerData[] = []
  private tableKeys: string[] = []

  created() {
    this.getList()
  }

  private async getList() {
    this.listLoading = true

    this.tableKeys = ['id', 'methods', 'upstreamType', 'uri']
    let { node: { nodes } } = await getList() as any
    nodes = [...nodes].map((item: any) => {
      const id = item.key.match(/\/([0-9]+)/)[1]
      let { methods, upstream, uri } = item.value
      methods = methods.join(', ')
      const upstreamType = upstream.type

      return {
        id,
        methods,
        upstream,
        uri,
        upstreamType
      }
    })

    this.tableData = nodes
    this.total = nodes.length

    console.log(nodes)

    setTimeout(() => {
      this.listLoading = false
    }, 0.5 * 1000)
  }

  private handleFilter() {
    this.listQuery.page = 1
    this.getList()
  }

  private handleRemove(row: any) {
    this.$confirm(`Do you want to remove router ${row.id}?`, 'Warning', {
      confirmButtonText: 'Confirm',
      cancelButtonText: 'Cancel',
      type: 'warning'
    })
      .then(async() => {
        await removeRouter(row.id)
        this.getList()
        this.$message.success(`Remove router ${row.id} successfully!`)
      })
  }

  private sortChange(data: any) {
    const { prop, order } = data
    if (prop === 'id') {
      this.sortByID(order)
    }
  }

  private sortByID(order: string) {
    if (order === 'ascending') {
      this.listQuery.sort = '+id'
    } else {
      this.listQuery.sort = '-id'
    }
    this.handleFilter()
  }

  private handleCreate() {
    this.$router.push({
      name: 'SchemaRoutesCreate'
    })
  }

  private handleToEdit(row: any) {
    this.$router.push({
      name: 'SchemaRoutesEdit',
      params: {
        id: row.id
      }
    })
  }
}
</script>
