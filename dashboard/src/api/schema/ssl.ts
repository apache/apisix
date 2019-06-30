import request from '@/utils/request'

import { ISSLData } from '../types'

export const getList = () =>
  request({
    url: '/ssl',
    method: 'GET'
  })

export const set = (id: string, params: ISSLData) =>
  request({
    url: `/ssl/${id}`,
    method: 'PUT',
    params
  })

export const get = (id: string) =>
  request({
    url: `/ssl/${id}`,
    method: 'GET'
  })

export const remove = (id: string) =>
  request({
    url: `/ssl/${id}`,
    method: 'DELETE'
  })

export const create = (params: ISSLData) =>
  request({
    url: '/ssl',
    method: 'POST',
    params
  })
