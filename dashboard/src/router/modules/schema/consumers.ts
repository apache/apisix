import { RouteConfig } from 'vue-router'
import Layout from '@/layout/index.vue'

const tableRoutes: RouteConfig = {
  path: '/schema/consumers',
  component: Layout,
  name: 'SchemaConsumers',
  meta: {
    title: 'SchemaConsumers',
    icon: 'table'
  },
  children: [
    {
      path: 'list',
      component: () => import(/* webpackChunkName: "complex-table" */ '@/views/schema/consumers/list.vue'),
      name: 'SchemaConsumersList',
      meta: { title: 'SchemaConsumersList' }
    }, {
      path: 'edit/:username',
      component: () => import('@/views/schema/consumers/edit.vue'),
      name: 'SchemaConsumersEdit',
      meta: {
        title: 'SchemaConsumersEdit',
        hidden: true
      }
    }, {
      path: 'create',
      component: () => import('@/views/schema/consumers/edit.vue'),
      name: 'SchemaConsumersCreate',
      meta: {
        title: 'SchemaConsumersCreate',
        hidden: true
      }
    }
  ]
}

export default tableRoutes
