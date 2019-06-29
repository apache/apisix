<template>
  <a
    :class="className"
    class="link--mallki"
    href="#"
  >
    {{ text }}
    <span :data-letters="text" />
    <span :data-letters="text" />
  </a>
</template>

<script lang="ts">
import { Component, Prop, Vue } from 'vue-property-decorator'

@Component({
  name: 'Mallki'
})
export default class extends Vue {
  @Prop({ default: '' }) private className!: string
  @Prop({ default: 'vue-typescript-admin' }) private text!: string
}
</script>

<style lang="scss" scoped>
/* Mallki */

.link--mallki {
  font-weight: 800;
  color: #4dd9d5;
  font-family: 'Dosis', sans-serif;
  -webkit-transition: color 0.5s 0.25s;
  transition: color 0.5s 0.25s;
  overflow: hidden;
  position: relative;
  display: inline-block;
  line-height: 1;
  outline: none;
  text-decoration: none;

  &:hover {
    -webkit-transition: none;
    transition: none;
    color: transparent;

    &::before {
      -webkit-transform: translate3d(100%, 0, 0);
      transform: translate3d(100%, 0, 0);
    }

    span::before {
      -webkit-transition-delay: 0.3s;
      transition-delay: 0.3s;
      -webkit-transform: translate3d(0, 0, 0);
      transform: translate3d(0, 0, 0);
      -webkit-transition-timing-function: cubic-bezier(0.2, 1, 0.3, 1);
      transition-timing-function: cubic-bezier(0.2, 1, 0.3, 1);
    }
  }

  &::before {
    content: '';
    width: 100%;
    height: 6px;
    margin: -3px 0 0 0;
    background: #3888fa;
    position: absolute;
    left: 0;
    top: 50%;
    -webkit-transform: translate3d(-100%, 0, 0);
    transform: translate3d(-100%, 0, 0);
    -webkit-transition: -webkit-transform 0.4s;
    transition: transform 0.4s;
    -webkit-transition-timing-function: cubic-bezier(0.7, 0, 0.3, 1);
    transition-timing-function: cubic-bezier(0.7, 0, 0.3, 1);
  }

  span {
    position: absolute;
    height: 50%;
    width: 100%;
    left: 0;
    top: 0;
    overflow: hidden;

    &::before {
      content: attr(data-letters);
      color: red;
      position: absolute;
      left: 0;
      width: 100%;
      color: #3888fa;
      -webkit-transition: -webkit-transform 0.5s;
      transition: transform 0.5s;
    }

    &:nth-child(2) {
      top: 50%;
    }

    &:first-child::before {
      top: 0;
      -webkit-transform: translate3d(0, 100%, 0);
      transform: translate3d(0, 100%, 0);
    }

    &:nth-child(2)::before {
      bottom: 0;
      -webkit-transform: translate3d(0, -100%, 0);
      transform: translate3d(0, -100%, 0);
    }
  }
}
</style>
