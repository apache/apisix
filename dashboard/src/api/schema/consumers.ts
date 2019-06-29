import request from '@/utils/request'

import { IConsumerData } from '../types'

export const updateOrCreate = (params: IConsumerData) =>
  request({
    url: '/consumers',
    method: 'PUT',
    params
  })

export const getList = () =>
request({
  url: '/consumers',
  method: 'GET'
})

export const get = (username: string) =>
  request({
    url: `/consumers/${username}`,
    method: 'GET'
  })

export const remove = (username: string) =>
  request({
    url: `/consumers/${username}`,
    method: 'DELETE'
  })