<template>
  <div class="app-container">
    <switch-roles @change="handleRolesChange" />
    <div
      :key="key"
      style="margin-top:30px;"
    >
      <div>
        <span
          v-permission="['admin']"
          class="permission-alert"
        >
          Only
          <el-tag
            class="permission-tag"
            size="small"
          >admin</el-tag> can see this
        </span>
        <el-tag
          v-permission="['admin']"
          class="permission-sourceCode"
          type="info"
        >
          v-permission="['admin']"
        </el-tag>
      </div>

      <div>
        <span
          v-permission="['editor']"
          class="permission-alert"
        >
          Only
          <el-tag
            class="permission-tag"
            size="small"
          >editor</el-tag> can see this
        </span>
        <el-tag
          v-permission="['editor']"
          class="permission-sourceCode"
          type="info"
        >
          v-permission="['editor']"
        </el-tag>
      </div>

      <div>
        <span
          v-permission="['admin','editor']"
          class="permission-alert"
        >
          Both
          <el-tag
            class="permission-tag"
            size="small"
          >admin</el-tag> and
          <el-tag
            class="permission-tag"
            size="small"
          >editor</el-tag> can see this
        </span>
        <el-tag
          v-permission="['admin','editor']"
          class="permission-sourceCode"
          type="info"
        >
          v-permission="['admin','editor']"
        </el-tag>
      </div>
    </div>

    <div
      :key="'checkPermission'+key"
      style="margin-top:60px;"
    >
      <aside>
        {{ $t('permission.tips') }}
        <br> e.g.
      </aside>

      <el-tabs
        type="border-card"
        style="width:550px;"
      >
        <el-tab-pane
          v-if="checkPermission(['admin'])"
          label="Admin"
        >
          Admin can see this
          <el-tag
            class="permission-sourceCode"
            type="info"
          >
            v-if="checkPermission(['admin'])"
          </el-tag>
        </el-tab-pane>

        <el-tab-pane
          v-if="checkPermission(['editor'])"
          label="Editor"
        >
          Editor can see this
          <el-tag
            class="permission-sourceCode"
            type="info"
          >
            v-if="checkPermission(['editor'])"
          </el-tag>
        </el-tab-pane>

        <el-tab-pane
          v-if="checkPermission(['admin','editor'])"
          label="Admin-OR-Editor"
        >
          Both admin or editor can see this
          <el-tag
            class="permission-sourceCode"
            type="info"
          >
            v-if="checkPermission(['admin','editor'])"
          </el-tag>
        </el-tab-pane>
      </el-tabs>
    </div>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import { checkPermission } from '@/utils/permission' // Use permission directly
import SwitchRoles from './components/SwitchRoles.vue'

@Component({
  name: 'DirectivePermission',
  components: {
    SwitchRoles
  }
})
export default class extends Vue {
  private key = 1 // 为了能每次切换权限的时候重新初始化指令
  private checkPermission = checkPermission

  private handleRolesChange() {
    this.key++
  }
}
</script>

<style lang="scss" scoped>
.permission-alert {
  width: 320px;
  margin-top: 15px;
  background-color: #f0f9eb;
  color: #67c23a;
  padding: 8px 16px;
  border-radius: 4px;
  display: inline-block;
}

.permission-sourceCode {
  margin-left: 15px;
}

.permission-tag {
  background-color: #ecf5ff;
}
</style>
