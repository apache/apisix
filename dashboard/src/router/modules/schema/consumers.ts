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
    }
  ]
}

export default tableRoutes
