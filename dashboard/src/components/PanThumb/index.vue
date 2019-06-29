<template>
  <div
    :style="{zIndex: zIndex, height: height, width: width}"
    class="pan-item"
  >
    <div class="pan-info">
      <div class="pan-info-roles-container">
        <slot />
      </div>
    </div>
    <div
      :style="{backgroundImage: `url(${image})`}"
      class="pan-thumb"
    />
  </div>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'

@Component({
  name: 'PanThumb'
})
export default class extends Vue {
  @Prop({ required: true }) private image!: string
  @Prop({ default: '150px' }) private width!: string
  @Prop({ default: '150px' }) private height!: string
  @Prop({ default: 1 }) private zIndex!: number
}
</script>

<style lang="scss" scoped>
.pan-item {
  width: 200px;
  height: 200px;
  border-radius: 50%;
  display: inline-block;
  position: relative;
  cursor: default;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);

  &:hover .pan-thumb {
    transform: rotate(-110deg);
  }

  &:hover .pan-info p a {
    opacity: 1;
    transform: translateX(0px) rotate(0deg);
  }
}

.pan-info {
  position: absolute;
  width: inherit;
  height: inherit;
  border-radius: 50%;
  overflow: hidden;
  box-shadow: inset 0 0 0 5px rgba(0, 0, 0, 0.05);

  .pan-info-roles-container {
    padding: 20px;
    text-align: center;
  }

  h3 {
    color: #fff;
    text-transform: uppercase;
    position: relative;
    letter-spacing: 2px;
    font-size: 18px;
    margin: 0 60px;
    padding: 22px 0 0 0;
    height: 85px;
    font-family: 'Open Sans', Arial, sans-serif;
    text-shadow: 0 0 1px #fff, 0 1px 2px rgba(0, 0, 0, 0.3);
  }

  p {
    color: #fff;
    padding: 10px 5px;
    font-style: italic;
    margin: 0 30px;
    font-size: 12px;
    border-top: 1px solid rgba(255, 255, 255, 0.5);

    a {
      display: block;
      color: #333;
      width: 80px;
      height: 80px;
      background: rgba(255, 255, 255, 0.3);
      border-radius: 50%;
      color: #fff;
      font-style: normal;
      font-weight: 700;
      text-transform: uppercase;
      font-size: 9px;
      letter-spacing: 1px;
      padding-top: 24px;
      margin: 7px auto 0;
      font-family: 'Open Sans', Arial, sans-serif;
      opacity: 0;
      transition: transform 0.3s ease-in-out 0.2s, opacity 0.3s ease-in-out 0.2s, background 0.2s linear 0s;
      transform: translateX(60px) rotate(90deg);

      &:hover {
        background: rgba(255, 255, 255, 0.5);
      }
    }
  }
}

.pan-thumb {
  width: 100%;
  height: 100%;
  background-position: center center;
  background-size: cover;
  border-radius: 50%;
  overflow: hidden;
  position: absolute;
  transform-origin: 95% 40%;
  transition: all 0.3s ease-in-out;
}
</style>
