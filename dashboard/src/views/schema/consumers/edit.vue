<template>
  <div class="consumers-wrapper">
    <el-form
      ref="form"
      :model="form"
      label-width="80px"
    >
      <el-form-item label="name">
        <el-input v-model="form.username" />
      </el-form-item>
      <el-form-item
        v-for="(item, index) of form.pluginNames"
        :key="index"
        :label="&quot;plugin&quot; + (index + 1)"
        class="plugin-item"
      >
        <el-button
          v-if="item"
          type="info"
          plain
        >
          {{ item }}
        </el-button>
        <el-select
          v-if="!item"
          v-model="form.pluginNames[index]"
          placeholder="Select a Plugin"
          class="plugin-select"
        >
          <el-option
            v-for="pluginName in filteredPluginList"
            :key="pluginName"
            :label="pluginName"
            :value="pluginName"
          />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button @click="addPlugin">
          Add Plugin
        </el-button>
      </el-form-item>

      <el-form-item>
        <el-button
          type="primary"
          @click="onSubmit"
        >
          Save
        </el-button>
        <el-button>Cancel</el-button>
      </el-form-item>
    </el-form>
  </div>
</template>

<script lang='ts'>
import { Component, Vue } from 'vue-property-decorator'

import { defaultConsumerData, getList, get } from '../../../api/schema/consumers'
import { getPluginList } from '../../../api/schema/plugins'

import { IArticleData, IConsumerData, IDataWrapper } from '../../../api/types'

@Component({
  name: 'ConsumerEdit'
})
export default class extends Vue {
  private form = {
    username: '',
    pluginNames: []
  }

  private pluginList = []

  get filteredPluginList() {
    return this.pluginList.filter(item => this.form.pluginNames.indexOf(item) < 0)
  }

  created() {
    this.getConsumerData()
    this.getPluginList()
  }

  private async getConsumerData() {
    const username = this.$route.params.username
    this.form.username = username

    const data: IDataWrapper<IConsumerData> = await get(username) as any
    console.log(data)

    const pluginNames: any[] = []
    Object.entries(data.node.value.plugins as any[]).map(([key, value]) => {
      pluginNames.push(key)
    })

    this.form.pluginNames = pluginNames as never
    console.log(this.form.pluginNames)
  }

  private async getPluginList() {
    this.pluginList = await getPluginList() as any
  }

  private async addPlugin() {
    (this.form as any).pluginNames.push(null)
  }

  private onSubmit() {
    console.log('submit!')
  }
}
</script>

<style lang='scss'>
.consumers-wrapper {
  padding: 20px;
  .el-form {
    .plugin-item {
      button {
        width: 150px;
      }
      .plugin-select {
        width: 150px;
      }
    }
  }
}
</style>
