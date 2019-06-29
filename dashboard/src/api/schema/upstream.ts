import request from '@/utils/request'

export const getRoles = (params: any) =>
  request({
    url: '/roles',
    method: 'get',
    params
  })