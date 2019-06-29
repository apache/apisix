import request from '@/utils/request'

export const getTransactions = (params: any) =>
  request({
    url: '/transactions',
    method: 'get',
    params
  })
