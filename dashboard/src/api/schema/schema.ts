import request from '@/utils/request'

export const getPluginSchema = (name: string) =>
  request({
    url: `/schema/plugins/${name}`,
    method: 'get'
  })
