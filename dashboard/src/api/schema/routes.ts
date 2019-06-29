import request from '@/utils/request'
import { IRouteData } from '../types'

export const getList = (id: string) =>
    request({
        url: '/routes',
        method: 'GET'
    })

export const update = (id: string, params: IRouteData) =>
    request({
        url: `/routes/${id}`,
        method: 'PUT',
        params
    })

export const get = (id: string) =>
    request({
        url: `/routes/${id}`,
        method: 'GET'
    })

export const remove = (id: string) =>
    request({
        url: `/routes/${id}`,
        method: 'DELETE'
    })

export const create = (params: IRouteData) =>
    request({
        url: '/routes',
        method: 'POST',
        params
    })
