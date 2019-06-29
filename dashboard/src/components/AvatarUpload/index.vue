<template>
  <image-crop-upload
    v-model="show"
    :field="field"
    :url="url"
    :width="width"
    :height="height"
    :params="params"
    :headers="headers"
    :lang-type="language"
    :with-credentials="true"
    img-format="png"
    @src-file-set="srcFileSet"
    @crop-success="cropSuccess"
    @crop-upload-success="cropUploadSuccess"
    @crop-upload-fail="cropUploadFail"
  />
</template>

<script lang="ts">
import ImageCropUpload from 'vue-image-crop-upload'
import { Component, Prop, Vue } from 'vue-property-decorator'
import { AppModule } from '@/store/modules/app'

@Component({
  name: 'AvatarUpload',
  components: {
    ImageCropUpload
  }
})
export default class extends Vue {
  // You can add more Prop, see: https://github.com/dai-siki/vue-image-crop-upload#usage
  @Prop({ required: true }) private value!: boolean
  @Prop({ required: true }) private url!: string
  @Prop({ required: true }) private field!: string
  @Prop({ default: 300 }) private width!: number
  @Prop({ default: 300 }) private height!: number
  @Prop({ default: () => {} }) private params!: object
  @Prop({ default: () => {} }) private headers!: object

  // https://github.com/dai-siki/vue-image-crop-upload#language-package
  private languageTypeList: { [key: string]: string } = {
    'en': 'en',
    'zh': 'zh',
    'es': 'es-MX',
    'ja': 'ja'
  }

  get show() {
    return this.value
  }

  set show(value) {
    this.$emit('input', value)
  }

  get language() {
    return this.languageTypeList[AppModule.language]
  }

  private srcFileSet(fileName: string, fileType: string, fileSize: number) {
    this.$emit('src-file-set', fileName, fileType, fileSize)
  }

  private cropSuccess(imgDataUrl: string, field: string) {
    this.$emit('crop-success', imgDataUrl, field)
  }

  private cropUploadSuccess(jsonData: any, field: string) {
    this.$emit('crop-upload-success', jsonData, field)
  }

  private cropUploadFail(status: boolean, field: string) {
    this.$emit('crop-upload-fail', status, field)
  }
}
</script>
