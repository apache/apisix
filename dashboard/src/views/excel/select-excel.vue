<template>
  <div class="app-container">
    <el-input
      v-model="filename"
      placeholder="Please enter the file name (default excel-list)"
      style="width:350px;"
      prefix-icon="el-icon-document"
    />
    <el-button
      :loading="downloadLoading"
      style="margin-bottom:20px"
      type="primary"
      icon="document"
      @click="handleDownload"
    >
      {{ $t('excel.selectedExport') }}
    </el-button>
    <a
      href="https://armour.github.io/vue-typescript-admin-docs/features/components/excel.html"
      target="_blank"
      style="margin-left:15px;"
    >
      <el-tag type="info">Documentation</el-tag>
    </a>
    <el-table
      ref="multipleTable"
      v-loading="listLoading"
      :data="list"
      element-loading-text="拼命加载中"
      border
      fit
      highlight-current-row
      @selection-change="handleSelectionChange"
    >
      <el-table-column
        type="selection"
        align="center"
      />
      <el-table-column
        align="center"
        label="Id"
        width="95"
      >
        <template slot-scope="scope">
          {{ scope.$index }}
        </template>
      </el-table-column>
      <el-table-column label="Title">
        <template slot-scope="scope">
          {{ scope.row.title }}
        </template>
      </el-table-column>
      <el-table-column
        label="Author"
        align="center"
        width="180"
      >
        <template slot-scope="scope">
          <el-tag>{{ scope.row.author }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column
        label="Readings"
        align="center"
        width="115"
      >
        <template slot-scope="scope">
          {{ scope.row.pageviews }}
        </template>
      </el-table-column>
      <el-table-column
        align="center"
        label="PDate"
        width="220"
      >
        <template slot-scope="scope">
          <i class="el-icon-time" />
          <span>{{ scope.row.timestamp }}</span>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import { getArticles } from '@/api/articles'
import { IArticleData } from '@/api/types'
import { formatJson } from '@/utils'
import { exportJson2Excel } from '@/utils/excel'
import { Table } from 'element-ui'

@Component({
  name: 'SelectExcel'
})
export default class extends Vue {
  private list: IArticleData[] = []
  private listLoading = true
  private multipleSelection = []
  private downloadLoading = false
  private filename = ''

  created() {
    this.fetchData()
  }

  private async fetchData() {
    this.listLoading = true
    const { data } = await getArticles({ /* Your params here */ })
    this.list = data.items
    // Just to simulate the time of the request
    setTimeout(() => {
      this.listLoading = false
    }, 0.5 * 1000)
  }

  private handleSelectionChange(value: any) {
    this.multipleSelection = value
  }

  private handleDownload() {
    if (this.multipleSelection.length) {
      this.downloadLoading = true
      const tHeader = ['Id', 'Title', 'Author', 'Readings', 'Date']
      const filterVal = ['id', 'title', 'author', 'pageviews', 'timestamp']
      const list = this.multipleSelection
      const data = formatJson(filterVal, list)
      exportJson2Excel(tHeader, data, this.filename !== '' ? this.filename : undefined);
      (this.$refs.multipleTable as Table).clearSelection()
      this.downloadLoading = false
    } else {
      this.$message({
        message: 'Please select at least one item',
        type: 'warning'
      })
    }
  }
}
</script>
