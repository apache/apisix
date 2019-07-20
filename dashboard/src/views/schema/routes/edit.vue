<template>
  <div class="container">
    <el-form
      ref="form"
      :model="form"
      :rules="rules"
      label-width="80px"
      :show-message="false"
    >
      <!-- Methods Multiple Selector: methods -->
      <!-- Upstream Single Selector: upstream_id -->
      <!-- URI -->
      <!-- HOST -->
      <!-- Plugin Multiple Selector -->
      <el-form-item>
        <el-button
          type="primary"
          @click="onSubmit"
        >
          Save
        </el-button>
        <el-button @click="toPreviousPage">
          Cancel
        </el-button>
      </el-form-item>
    </el-form>
  </div>
</template>

<script lang='ts'>
import { Component, Vue } from 'vue-property-decorator'
import { Form } from 'element-ui'

import { getRouter } from '../../../api/schema/routes'


@Component({
  name: 'RouterEdit'
})

export default class extends Vue {
  private form = {
    methods: [],
    upstream: {
      nodes: {},
      type: '',
    },
    uri: '',
    plugins: {},
  }

  private rules = {}
  private isEditMode: boolean = false

  created() {
    this.isEditMode = (this.$route as any).name.indexOf('Create') === -1

    if (this.isEditMode) {
      this.getData()
    }
  }

  private async getData() {
    const { id } = this.$route.params
    const { node: { value } } = await getRouter(id) as any
    const { methods, upstream, uri, plugins, } = value
    this.form = {
      methods,
      upstream,
      uri,
      plugins: {},
    }
  }

  private async onSubmit() {
    console.log('onSubmit')
  }

  private toPreviousPage() {
    this.$router.go(-1)
  }
}
</script>

<style lang='scss'>
.container {
  padding: 20px;
  .el-form {}
}
</style>
