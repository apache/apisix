import { RouteConfig } from 'vue-router'
import Layout from '@/layout/index.vue'

const tableRoutes: RouteConfig = {
  path: '/schema/upstream',
  component: Layout,
  name: 'SchemaUpstream',
  meta: {
    title: 'SchemaUpstream',
    icon: 'table'
  },
  children: [
    {
      path: 'list',
      component: () => import(/* webpackChunkName: "complex-table" */ '@/views/table/complex-table.vue'),
      name: 'SchemaUpstreamList',
      meta: { title: 'SchemaUpstreamList' }
    }
  ]
}

export default tableRoutes
