<template>
  <div>
    <input
      ref="excel-upload-input"
      class="excel-upload-input"
      type="file"
      accept=".xlsx, .xls"
      @change="handleClick"
    >
    <div
      class="drop"
      @drop="handleDrop"
      @dragover="handleDragover"
      @dragenter="handleDragover"
    >
      Drop excel file here or
      <el-button
        :loading="loading"
        style="margin-left:16px;"
        size="mini"
        type="primary"
        @click="handleUpload"
      >
        Browse
      </el-button>
    </div>
  </div>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'
import XLSX from 'xlsx'

@Component({
  name: 'UploadExcel'
})
export default class extends Vue {
  @Prop({ required: true }) private beforeUpload!: Function
  @Prop({ required: true }) private onSuccess!: Function

  private loading = false
  private excelData = {
    header: null,
    results: null
  }

  private generateData(header: any, results: any) {
    this.excelData.header = header
    this.excelData.results = results
    this.onSuccess && this.onSuccess(this.excelData)
  }

  private handleDrop(e: DragEvent) {
    e.stopPropagation()
    e.preventDefault()
    if (this.loading) return
    if (!e.dataTransfer) return
    const files = e.dataTransfer.files
    if (files.length !== 1) {
      this.$message.error('Only support uploading one file!')
      return
    }
    const rawFile = files[0] // only use files[0]

    if (!this.isExcel(rawFile)) {
      this.$message.error('Only supports upload .xlsx, .xls, .csv suffix files')
      return false
    }
    this.upload(rawFile)
    e.stopPropagation()
    e.preventDefault()
  }

  private handleDragover(e: DragEvent) {
    e.stopPropagation()
    e.preventDefault()
    if (e.dataTransfer) {
      e.dataTransfer.dropEffect = 'copy'
    }
  }

  private handleUpload() {
    (this.$refs['excel-upload-input'] as HTMLInputElement).click()
  }

  private handleClick(e: MouseEvent) {
    const files = (e.target as HTMLInputElement).files
    if (files) {
      const rawFile = files[0] // only use files[0]
      this.upload(rawFile)
    }
  }

  private upload(rawFile: File) {
    (this.$refs['excel-upload-input'] as HTMLInputElement).value = '' // Fixes can't select the same excel
    if (!this.beforeUpload) {
      this.readerData(rawFile)
      return
    }
    const before = this.beforeUpload(rawFile)
    if (before) {
      this.readerData(rawFile)
    }
  }

  private readerData(rawFile: File) {
    this.loading = true
    const reader = new FileReader()
    reader.onload = e => {
      const data = (e.target as FileReader).result
      const workbook = XLSX.read(data, { type: 'array' })
      const firstSheetName = workbook.SheetNames[0]
      const worksheet = workbook.Sheets[firstSheetName]
      const header = this.getHeaderRow(worksheet)
      const results = XLSX.utils.sheet_to_json(worksheet)
      this.generateData(header, results)
      this.loading = false
    }
    reader.readAsArrayBuffer(rawFile)
  }

  private getHeaderRow(sheet: { [key: string ]: any }) {
    const headers: string[] = []
    const range = XLSX.utils.decode_range(sheet['!ref'])
    const R = range.s.r
    // start in the first row
    for (let C = range.s.c; C <= range.e.c; ++C) { // walk every column in the range
      const cell = sheet[XLSX.utils.encode_cell({ c: C, r: R })]
      // find the cell in the first row
      let hdr: string = ''
      if (cell && cell.t) hdr = XLSX.utils.format_cell(cell)
      if (hdr === '') {
        hdr = 'UNKNOWN ' + C // replace with your desired default
      }
      headers.push(hdr)
    }
    return headers
  }

  private isExcel(file: File) {
    return /\.(xlsx|xls|csv)$/.test(file.name)
  }
}
</script>

<style lang="scss" scoped>
.excel-upload-input {
  display: none;
  z-index: -9999;
}

.drop {
  border: 2px dashed #bbb;
  width: 600px;
  height: 160px;
  line-height: 160px;
  margin: 0 auto;
  font-size: 24px;
  border-radius: 5px;
  text-align: center;
  color: #bbb;
  position: relative;
}
</style>
