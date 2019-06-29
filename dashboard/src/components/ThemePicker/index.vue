<template>
  <el-color-picker
    v-model="theme"
    :predefine="['#409EFF', '#1890ff', '#304156','#212121','#11a983', '#13c2c2', '#6959CD', '#f5222d']"
    class="theme-picker"
    popper-class="theme-picker-dropdown"
  />
</template>

<script lang="ts">
import { Component, Prop, Vue, Watch } from 'vue-property-decorator'
import { SettingsModule } from '@/store/modules/settings'

const version = require('element-ui/package.json').version // element-ui version from node_modules
const ORIGINAL_THEME = '#409EFF' // default color

@Component({
  name: 'ThemePicker'
})
export default class extends Vue {
  private chalk = '' // The content of theme-chalk css
  private theme = ''

  get defaultTheme() {
    return SettingsModule.theme
  }

  @Watch('defaultTheme', { immediate: true })
  private onDefaultThemeChange(value: string) {
    this.theme = value
  }

  @Watch('theme')
  private async onThemeChange(value: string) {
    if (!value) return
    const oldValue = this.chalk ? this.theme : ORIGINAL_THEME
    const themeCluster = this.getThemeCluster(value.replace('#', ''))
    const originalCluster = this.getThemeCluster(oldValue.replace('#', ''))
    const message = this.$message({
      message: '  Compiling the theme',
      customClass: 'theme-message',
      type: 'success',
      duration: 0,
      iconClass: 'el-icon-loading'
    })

    if (!this.chalk) {
      const url = `https://unpkg.com/element-ui@${version}/lib/theme-chalk/index.css`
      await this.getCSSString(url, 'chalk')
    }

    const getHandler = (variable: string, id: string) => {
      return () => {
        const originalCluster = this.getThemeCluster(ORIGINAL_THEME.replace('#', ''))
        const newStyle = this.updateStyle((this as any)[variable], originalCluster, themeCluster)

        let styleTag = document.getElementById(id)
        if (!styleTag) {
          styleTag = document.createElement('style')
          styleTag.setAttribute('id', id)
          document.head.appendChild(styleTag)
        }
        styleTag.innerText = newStyle
      }
    }
    const chalkHandler = getHandler('chalk', 'chalk-style')
    chalkHandler()

    let styles: HTMLElement[] = [].slice.call(document.querySelectorAll('style'))
    styles = styles
      .filter(style => {
        const text = style.innerText
        return new RegExp(oldValue, 'i').test(text) && !/Chalk Variables/.test(text)
      })
    styles.forEach(style => {
      const { innerText } = style
      if (typeof innerText !== 'string') return
      style.innerText = this.updateStyle(innerText, originalCluster, themeCluster)
    })

    this.$emit('change', value)
    message.close()
  }

  private updateStyle(style: string, oldCluster: string[], newCluster: string[]) {
    let newStyle = style
    oldCluster.forEach((color, index) => {
      newStyle = newStyle.replace(new RegExp(color, 'ig'), newCluster[index])
    })
    return newStyle
  }

  private getCSSString(url: string, variable: string) {
    return new Promise(resolve => {
      const xhr = new XMLHttpRequest()
      xhr.onreadystatechange = () => {
        if (xhr.readyState === 4 && xhr.status === 200) {
          (this as any)[variable] = xhr.responseText.replace(/@font-face{[^}]+}/, '')
          resolve()
        }
      }
      xhr.open('GET', url)
      xhr.send()
    })
  }

  private getThemeCluster(theme: string) {
    const tintColor = (color: string, tint: number) => {
      let red = parseInt(color.slice(0, 2), 16)
      let green = parseInt(color.slice(2, 4), 16)
      let blue = parseInt(color.slice(4, 6), 16)
      if (tint === 0) { // when primary color is in its rgb space
        return [red, green, blue].join(',')
      } else {
        red += Math.round(tint * (255 - red))
        green += Math.round(tint * (255 - green))
        blue += Math.round(tint * (255 - blue))
        return `#${red.toString(16)}${green.toString(16)}${blue.toString(16)}`
      }
    }

    const shadeColor = (color: string, shade: number) => {
      let red = parseInt(color.slice(0, 2), 16)
      let green = parseInt(color.slice(2, 4), 16)
      let blue = parseInt(color.slice(4, 6), 16)
      red = Math.round((1 - shade) * red)
      green = Math.round((1 - shade) * green)
      blue = Math.round((1 - shade) * blue)
      return `#${red.toString(16)}${green.toString(16)}${blue.toString(16)}`
    }

    const clusters = [theme]
    for (let i = 0; i <= 9; i++) {
      clusters.push(tintColor(theme, Number((i / 10).toFixed(2))))
    }
    clusters.push(shadeColor(theme, 0.1))
    return clusters
  }
}
</script>

<style lang="scss">
.theme-message,
.theme-picker-dropdown {
  z-index: 99999 !important;
}

.theme-picker .el-color-picker__trigger {
  height: 26px !important;
  width: 26px !important;
  padding: 2px;
}

.theme-picker-dropdown .el-color-dropdown__link-btn {
  display: none;
}
</style>
