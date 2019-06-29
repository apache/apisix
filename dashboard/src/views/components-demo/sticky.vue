<template>
  <div>
    <sticky
      :z-index="10"
      class-name="sub-navbar"
    >
      <el-dropdown trigger="click">
        <el-button plain>
          Platform<i class="el-icon-caret-bottom el-icon--right" />
        </el-button>
        <el-dropdown-menu
          slot="dropdown"
          class="no-border"
        >
          <el-checkbox-group
            v-model="platforms"
            style="padding: 5px 15px;"
          >
            <el-checkbox
              v-for="item in platformsOptions"
              :key="item.key"
              :label="item.key"
            >
              {{ item.name }}
            </el-checkbox>
          </el-checkbox-group>
        </el-dropdown-menu>
      </el-dropdown>

      <el-dropdown trigger="click">
        <el-button plain>
          Link<i class="el-icon-caret-bottom el-icon--right" />
        </el-button>
        <el-dropdown-menu
          slot="dropdown"
          class="no-padding no-border"
          style="width: 300px"
        >
          <el-input
            v-model="url"
            placeholder="Please enter the content"
          >
            <template slot="prepend">
              Url
            </template>
          </el-input>
        </el-dropdown-menu>
      </el-dropdown>

      <div class="time-container">
        <el-date-picker
          v-model="time"
          type="datetime"
          format="yyyy-MM-dd HH:mm:ss"
          placeholder="Release time"
          :picker-options="pickerOptions"
        />
      </div>

      <el-button
        style="margin-left: 10px;"
        type="success"
      >
        publish
      </el-button>
    </sticky>

    <div class="components-container">
      <aside>Sticky header, {{ $t('components.stickyTips') }}</aside>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <sticky :sticky-top="200">
        <el-button
          type="primary"
        >
          placeholder
        </el-button>
      </sticky>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
      <div>placeholder</div>
    </div>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import Sticky from '@/components/Sticky/index.vue'

@Component({
  name: 'StickyDemo',
  components: {
    Sticky
  }
})
export default class extends Vue {
  private time = Date
  private url = ''
  private platforms = ['a-platform']
  private platformsOptions = [
    { key: 'a-platform', name: 'platformA' },
    { key: 'b-platform', name: 'platformB' },
    { key: 'c-platform', name: 'platformC' }
  ]
  private pickerOptions = {
    disabledDate(time: Date) {
      return time.getTime() > Date.now()
    }
  }
}
</script>

<style lang="scss" scoped>
.components-container div {
  margin: 10px;
}

.time-container {
  display: inline-block;
}
</style>
