import request from '@/utils/request'

import { IConsumerData } from '../types'

export const defaultConsumerData: IConsumerData = {
  username: '',
  plugins: {}
}

export const updateOrCreateConsumer = (data: IConsumerData) =>
  request({
    url: '/consumers',
    method: 'PUT',
    data
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

export const removeConsumer = (username: string) =>
  request({
    url: `/consumers/${username}`,
    method: 'DELETE'
  })
