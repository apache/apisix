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
            @click="handleUpdate(row)"
          >
            {{ $t('table.edit') }}
          </el-button>

          <el-button
            v-if="row.status!=='deleted'"
            size="mini"
            type="danger"
            @click="handleModifyStatus(row,'deleted')"
          >
            {{ $t('table.delete') }}
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog
      :title="textMap[dialogStatus]"
      :visible.sync="dialogFormVisible"
    >
      <el-form
        ref="dataForm"
        :rules="rules"
        :model="tempData"
        label-position="left"
        label-width="100px"
        style="width: 400px; margin-left:50px;"
      >
        <el-form-item
          label="username"
          prop="username"
        >
          <el-input v-model="tempData.username" />
        </el-form-item>

        <el-form-item
          v-for="(item, index) of tempData.pluginArr"
          :key="index"
          :label="'plugin' + index"
          style="width:500px"
        >
          <el-input
            v-model="item[fieldName]"
            style="display:inline-block;width:120px;margin-right:10px;"
            v-for="fieldName of ['name','key']"
            :key="fieldName"
            :placeholder="fieldName"
          />
          <el-button
            type="danger"
            style="margin-top:10px;"
            @click.prevent="removePlugin(item)"
          >
            Delete
          </el-button>
        </el-form-item>
        <el-form-item>
          <el-button @click="addPlugin">
            Add Plugin
          </el-button>
        </el-form-item>
      </el-form>
      <div
        slot="footer"
        class="dialog-footer"
      >
        <el-button @click="dialogFormVisible = false">
          {{ $t('table.cancel') }}
        </el-button>
        <el-button
          type="primary"
          @click="dialogStatus==='create'?createData():updateData()"
        >
          {{ $t('table.confirm') }}
        </el-button>
      </div>
    </el-dialog>

    <el-dialog
      :visible.sync="dialogPageviewsVisible"
      title="Reading statistics"
    >
      <el-table
        :data="pageviewsData"
        border
        fit
        highlight-current-row
        style="width: 100%"
      >
        <el-table-column
          prop="key"
          label="Channel"
        />
        <el-table-column
          prop="pageviews"
          label="Pageviews"
        />
      </el-table>
      <span
        slot="footer"
        class="dialog-footer"
      >
        <el-button
          type="primary"
          @click="dialogPageviewsVisible = false"
        >{{ $t('table.confirm') }}</el-button>
      </span>
    </el-dialog>
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
  private importanceOptions = [1, 2, 3]
  private sortOptions = [
    { label: 'ID Ascending', key: '+id' },
    { label: 'ID Descending', key: '-id' }
  ]
  private statusOptions = ['published', 'draft', 'deleted']
  private showReviewer = false
  private dialogFormVisible = false
  private dialogStatus = ''
  private textMap = {
    update: 'Edit',
    create: 'Create'
  }
  private dialogPageviewsVisible = false
  private pageviewsData = []
  private rules = {
    type: [{ required: true, message: 'type is required', trigger: 'change' }],
    timestamp: [{ required: true, message: 'timestamp is required', trigger: 'change' }],
    title: [{ required: true, message: 'title is required', trigger: 'blur' }]
  }
  private downloadLoading = false
  private tempArticleData = defaultArticleData

  private tableData: IConsumerData[] = []
  private tableKeys: string[] = []

  private tempData: IConsumerData = defaultConsumerData

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

      Object.entries(value.plugins).map(([ key, value ]: any) => {
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

  private addPlugin() {
    (this.tempData as any).pluginArr.push({
      name: null,
      key: null
    })
  }

  private removePlugin(item: any) {
    const index = (this.tempData as any).pluginArr.indexOf(item)

    if (index !== -1) {
      (this.tempData as any).pluginArr.splice(index, 1)
      console.log({
        index, tempData: this.tempData
      })
    }
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

  private resetTempArticleData() {
    this.tempArticleData = defaultArticleData
  }

  private handleCreate() {
    this.resetTempArticleData()
    this.dialogStatus = 'create'
    this.dialogFormVisible = true
    this.$nextTick(() => {
      (this.$refs['dataForm'] as Form).clearValidate()
    })
  }

  private createData() {
    (this.$refs['dataForm'] as Form).validate(async(valid) => {
      if (valid) {
        let { id, ...articleData } = this.tempArticleData
        articleData.author = 'vue-element-admin'
        const { data } = await createArticle({ article: articleData })
        this.list.unshift(data.article)
        this.dialogFormVisible = false
        this.$notify({
          title: '成功',
          message: '创建成功',
          type: 'success',
          duration: 2000
        })
      }
    })
  }

  private handleUpdate(row: any) {
    this.tempData = Object.assign({}, row)
    console.log(this.tempData)
    this.dialogStatus = 'update'
    this.dialogFormVisible = true
    this.$nextTick(() => {
      (this.$refs['dataForm'] as Form).clearValidate()
    })
  }

  private updateData() {
    (this.$refs['dataForm'] as Form).validate(async(valid) => {
      if (valid) {
        const tempData = Object.assign({}, this.tempData)

        // const { data } = await updateArticle(tempData.id, { article: tempData })
        
        // for (const v of this.list) {
        //   if (v.id === data.article.id) {
        //     const index = this.list.indexOf(v)
        //     this.list.splice(index, 1, data.article)
        //     break
        //   }
        // }

        this.dialogFormVisible = false
        this.$notify({
          title: '成功',
          message: '更新成功',
          type: 'success',
          duration: 2000
        })
      }
    })
  }

  private async handleGetPageviews(pageviews: string) {
    const { data } = await getPageviews({ /* Your params here */ })
    this.pageviewsData = data.pageviews
    this.dialogPageviewsVisible = true
  }

  private handleDownload() {
    this.downloadLoading = true
    const tHeader = ['timestamp', 'title', 'type', 'importance', 'status']
    const filterVal = ['timestamp', 'title', 'type', 'importance', 'status']
    const data = formatJson(filterVal, this.list)
    exportJson2Excel(tHeader, data, 'table-list')
    this.downloadLoading = false
  }
}
</script>
