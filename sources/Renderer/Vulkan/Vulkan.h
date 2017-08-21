/*
 * Vulkan.h
 * 
 * This file is part of the "LLGL" project (Copyright (c) 2015-2017 by Lukas Hermanns)
 * See "LICENSE.txt" for license information.
 */

#ifndef LLGL_VULKAN_H
#define LLGL_VULKAN_H


#include <LLGL/Platform/Platform.h>

#if defined(LLGL_OS_WIN32)
#   define VK_USE_PLATFORM_WIN32_KHR
#elif defined(LLGL_OS_LINUX)
#   define VK_USE_PLATFORM_XLIB_KHR
#else
#   error unsupported platform for Vulkan
#endif

#include <vulkan/vulkan.h>


#endif



// ================================================================================
