import request from '@/utils/request'

export const getPluginList = () =>
  request({
    url: '/plugins/list',
    method: 'get'
  })
