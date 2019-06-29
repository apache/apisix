import { RouteConfig } from 'vue-router'
import Layout from '@/layout/index.vue'

const tableRoutes: RouteConfig = {
  path: '/schema/services',
  component: Layout,
  name: 'SchemaServices',
  meta: {
    title: 'SchemaServices',
    icon: 'table'
  },
  children: [
    {
      path: 'list',
      component: () => import(/* webpackChunkName: "complex-table" */ '@/views/table/complex-table.vue'),
      name: 'SchemaServicesList',
      meta: { title: 'SchemaServicesList' }
    }
  ]
}

export default tableRoutes
