import { RouteConfig } from 'vue-router'
import Layout from '@/layout/index.vue'

const tableRoutes: RouteConfig = {
  path: '/schema/routes',
  component: Layout,
  name: 'SchemaRoutes',
  meta: {
    title: 'SchemaRoutes',
    icon: 'table'
  },
  children: [
    {
      path: 'list',
      component: () => import(/* webpackChunkName: "complex-table" */ '@/views/table/complex-table.vue'),
      name: 'SchemaRoutesList',
      meta: { title: 'SchemaRoutesList' }
    }
  ]
}

export default tableRoutes
