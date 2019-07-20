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
      component: () => import('@/views/schema/routes/list.vue'),
      name: 'SchemaRoutesList',
      meta: { title: 'SchemaRoutesList' }
    }, {
      path: 'edit/:id',
      component: () => import('@/views/schema/routes/edit.vue'),
      name: 'SchemaRoutesEdit',
      meta: {
        title: 'SchemaRoutesEdit',
        hidden: true
      }
    }, {
      path: 'create',
      component: () => import('@/views/schema/routes/edit.vue'),
      name: 'SchemaRoutesCreate',
      meta: {
        title: 'SchemaRoutesCreate',
        hidden: true
      }
    }
  ]
}

export default tableRoutes
