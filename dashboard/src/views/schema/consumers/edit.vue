<template>
  <div class="consumers-wrapper">
    <el-form
      ref="form"
      :model="form"
      :rules="rules"
      label-width="80px"
      :show-message="false"
    >
      <el-form-item
        label="name"
        prop="username"
      >
        <el-input v-model="form.username" />
      </el-form-item>
      <el-form-item
        v-for="(index, item) in form.plugins"
        :key="item"
        :label="&quot;plugin&quot;"
        class="plugin-item"
      >
        <el-button
          v-if="item && item !== 'temp'"
          type="info"
          plain
          @click="showPlugin(item)"
        >
          {{ item }}
        </el-button>
        <el-select
          v-if="item === 'temp'"
          value=""
          class="plugin-select"
          placeholder="Select a Plugin"
          @change="handleSelectPlugin"
        >
          <el-option
            v-for="name in filteredPluginList"
            :key="name"
            :label="name"
            :value="name"
          />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button
          :disabled="!filteredPluginList.length"
          @click="addPlugin"
        >
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
        <el-button @click="handleToPreviousPage">
          Cancel
        </el-button>
      </el-form-item>
    </el-form>

    <el-dialog
      :title="'Plugin ' + pluginSchema.pluginName + ' Edit'"
      :visible.sync="showPluginEditDialog"
    >
      <el-form
        ref="pluginForm"
        :model="form.plugins[pluginSchema.pluginName]"
        :rules="pluginRules"
        :show-message="false"
      >
        <!-- BUG: 由于使用 v-model 绑定了值，在不点击 Save 的情况下也会将值更新到相应插件对象上 -->
        <el-form-item
          v-for="(index, key) in pluginSchema.properties"
          :key="key"
          :label="key"
          label-width="160px"
          :prop="key"
        >
          <!-- 分情况讨论 -->
          <el-input-number
            v-if="pluginSchema.properties[key].type === 'integer' || pluginSchema.properties[key].type === 'number'"
            v-model="form.plugins[pluginSchema.pluginName][key]"
            :min="pluginSchema.properties[key].minimum || -99999999999"
            :max="pluginSchema.properties[key].maximum || 99999999999"
            label="描述文字"
            @change="handlePluginPropertyChange(key, $event)"
          />

          <el-select
            v-if="pluginSchema.properties[key].hasOwnProperty('enum')"
            v-model="form.plugins[pluginSchema.pluginName][key]"
            :placeholder="&quot;Select a &quot; + key"
            @change="handlePluginPropertyChange(key, $event)"
          >
            <el-option
              v-for="value in pluginSchema.properties[key]['enum']"
              :key="value"
              :label="value"
              :value="value"
            />
          </el-select>

          <el-input
            v-if="pluginSchema.properties[key].type === 'string' && !pluginSchema.properties[key].hasOwnProperty('enum')"
            v-model="form.plugins[pluginSchema.pluginName][key]"
            :placeholder="key"
          />
        </el-form-item>
      </el-form>
      <span
        slot="footer"
        class="dialog-footer"
      >
        <el-button
          @click="showPluginEditDialog = false"
        >
          Cancel
        </el-button>
        <el-button
          type="primary"
          @click="savePlugin"
        >
          Save
        </el-button>
      </span>
    </el-dialog>
  </div>
</template>

<script lang='ts'>
import { Component, Vue } from 'vue-property-decorator'
import { Form } from 'element-ui'

import { defaultConsumerData, getList, get, updateOrCreateConsumer } from '../../../api/schema/consumers'
import { getPluginList } from '../../../api/schema/plugins'
import { getPluginSchema } from '../../../api/schema/schema'

import { IArticleData, IConsumerData, IDataWrapper } from '../../../api/types'

const uuidv1 = require('uuid/v1')

@Component({
  name: 'ConsumerEdit'
})
export default class extends Vue {
  private form = {
    username: '',
    plugins: {}
  }

  private pluginList = []
  private showPluginEditDialog = false
  private pluginSchema: any = {
    pluginName: ''
  }
  private pluginRules = {}
  private rules = {
    username: {
      required: true
    }
  }

  private isEditMode: boolean = false

  get filteredPluginList() {
    return this.pluginList.filter(item => !this.form.plugins.hasOwnProperty(item))
  }

  created() {
    this.isEditMode = (this.$route as any).name.indexOf('Create') === -1

    if (this.isEditMode) {
      this.getConsumerData()
    }

    this.getPluginList()
  }

  private async getConsumerData() {
    const username = this.$route.params.username
    const data: IDataWrapper<IConsumerData> = await get(username) as any

    (this.form as any) = {
      username,
      plugins: data.node.value.plugins
    }
  }

  private async getPluginList() {
    this.pluginList = await getPluginList() as any
  }

  private async addPlugin() {
    // TODO: https://github.com/iresty/apisix/blob/master/lua/apisix/core/schema.lua description
    // TODO: schema 添加 defaultValue
    if (this.form.plugins.hasOwnProperty('temp')) return

    this.form.plugins = {
      ...this.form.plugins,
      temp: null
    }
  }

  private async onSubmit() {
    for (let name in this.form.plugins) {
      // NOTE: 此处若存在 temp 临时空对象，则会附着在 PUT 请求中，暂未移除
      if (name !== 'temp' && !(this.form.plugins as any)[name]._isValid) {
        const schema = await getPluginSchema(name) as any
        if (!schema.properties || (schema.properties && !schema.required)) {
          (this.form as any).plugins[name]._isValid = true
        } else {
          this.$message.error(`Plugin ${name} is invalid!`)
          return
        }
      }
    }

    (this.$refs['form'] as any).validate(async(valid: boolean) => {
      if (valid) {
        let data = Object.assign({}, this.form)
        for (let name in data.plugins) {
          delete (data.plugins as any)[name]._isValid
        }
        await updateOrCreateConsumer(data)

        this.$message.success(`${this.isEditMode ? 'Edit the' : 'Create a'} consumer successfully!`)

        if (this.isEditMode) return

        this.$nextTick(() => {
          this.pluginSchema = {}
          this.pluginRules = {}
          this.form = {
            username: '',
            plugins: {}
          }
        })
      } else {
        return false
      }
    })
  }

  private async showPlugin(name: string) {
    const schema = await getPluginSchema(name) as any

    if (!schema.properties) return

    this.pluginSchema = {
      ...schema,
      pluginName: name
    }

    console.log({
      form: Object.assign({}, this.form),
      schema: this.pluginSchema
    })

    const rules = Object.assign({}, schema.properties)
    for (let pluginName in rules) {
      const plugin = Object.assign({}, rules[pluginName])

      rules[pluginName] = {
        trigger: 'blur'
      }

      if (schema.required) {
        rules[pluginName].required = schema.required.includes(pluginName)
      }

      if (plugin.hasOwnProperty('type')) {
        rules[pluginName]['type'] = plugin['type']
      }

      if (plugin.hasOwnProperty('minimum')) {
        rules[pluginName]['min'] = plugin['minimum']
      }

      if (plugin.hasOwnProperty('maximum')) {
        rules[pluginName]['max'] = plugin['maximum']
      }

      if (plugin.hasOwnProperty('enum')) {
        rules[pluginName]['type'] = 'enum'
        rules[pluginName]['enum'] = plugin['enum']
      }
    }

    this.pluginRules = rules

    this.showPluginEditDialog = true
  }

  private async handleSelectPlugin(key: string) {
    delete (this.form.plugins as any)['temp']
    const schema = await getPluginSchema(key) as any

    this.form.plugins = {
      ...this.form.plugins,
      [key]: {
        _isValid: !schema.properties
      }
    }

    if (key === 'key-auth') {
      // NOTE: 特殊处理
      this.form.plugins['key-auth']['key'] = uuidv1()
    }

    // NOTE: 将导致产生两次 plugin schema 请求
    this.showPlugin(key)
  }

  private handlePluginPropertyChange(key: any, value: any) {
    console.log('handlePluginPropertyChange', {
      key, value, pluginName: this.pluginSchema.pluginName
    })

    this.form.plugins[this.pluginSchema.pluginName][key] = value
  }

  private savePlugin() {
    (this.$refs['pluginForm'] as any).validate((valid: boolean) => {
      console.log('form', this.form)
      // 标记该插件数据是否通过校验
      this.form.plugins[this.pluginSchema.pluginName]._isValid = valid
      if (valid) {
        this.showPluginEditDialog = false
      } else {
        return false
      }
    })
  }

  private handleToPreviousPage() {
    this.$router.go(-1)
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
