import { RouteConfig } from 'vue-router'
import Layout from '@/layout/index.vue'

const tableRoutes: RouteConfig = {
  path: '/schema/ssl',
  component: Layout,
  name: 'SchemaSSL',
  meta: {
    title: 'SchemaSSL',
    icon: 'table'
  },
  children: [
    {
      path: 'list',
      component: () => import(/* webpackChunkName: "complex-table" */ '@/views/table/complex-table.vue'),
      name: 'SchemaSSLList',
      meta: { title: 'SchemaSSLList' }
    }
  ]
}

export default tableRoutes
