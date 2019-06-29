import request from '@/utils/request'
import { IServiceData } from '../types'

export const getList = () =>
  request({
    url: '/services',
    method: 'get'
  })

export const update = (id: string, params: IServiceData) =>
  request({
    url: `/services/${id}`,
    method: 'PUT',
    params
  })

export const get = (id: string) =>
  request({
    url: `/services/${id}`,
    method: 'GET'
  })

export const remove = (id: string) =>
  request({
    url: `/services/${id}`,
    method: 'DELETE'
  })

export const create = (params: IServiceData) =>
  request({
    url: '/services',
    method: 'POST',
    params
  })
