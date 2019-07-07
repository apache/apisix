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
            @click="handleModifyStatus(row, 'deleted')"
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

import { defaultConsumerData, getList } from '../../../api/schema/consumers'

@Component({
  name: 'ComplexTable',
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

    this.tableKeys = ['username', 'plugins']

    const _list = await getList() as any
    const list: IConsumerData[] = _list.map((item: IDataWrapper<IConsumerData>) => {
      const value = Object.assign({}, item.node.value)
      const pluginArr: any[] = []

      Object.entries(value.plugins as any).map(([ key, value ]: any) => {
        pluginArr.push({
          name: key,
          key: value.key
        })
      })

      return {
        ...value,
        plugins: pluginArr.map(item => item.name).join(', '),
        pluginArr
      }
    })

    console.log({
      list
    })

    this.tableData = list
    this.total = list.length

    // Just to simulate the time of the request
    setTimeout(() => {
      this.listLoading = false
    }, 0.5 * 1000)
  }

  private handleFilter() {
    this.listQuery.page = 1
    this.getList()
  }

  private handleModifyStatus(row: any, status: string) {
    this.$message({
      message: '操作成功',
      type: 'success'
    })
    row.status = status
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
    // TODO: 跳转至 Edit 页
  }

  private handleToEdit(row: any) {
    this.$router.push({
      name: 'SchemaConsumersEdit',
      params: {
        username: row.username
      }
    })
  }
}
</script>
