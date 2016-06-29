local image = require 'image'
local paths = require 'paths'
local t = require 'datasets/transforms'
local ffi = require 'ffi'

local M = {}
local ImagenetDataset = torch.class('nn.ImagenetDataset', M)

function ImagenetDataset:__init(imageInfo, opt, split)
    self.imageInfo = imageInfo[split]
    self.opt = opt
    self.split = split
    self.dir = paths.concat(opt.data, split)
    self.perm = torch.LongTensor{3, 2, 1}
    if self.opt.externalMeanFile then
        print("loading from externel mean file " .. self.opt.externalMeanFile)
        self.meanstd = torch.load(self.opt.externalMeanFile)
    else
        print("Using internal mean file")
        self.meanstd = {
            mean = {103.939, 116.779, 123.68},
            std = {1, 1, 1}
        }
    end
    assert(paths.dirp(self.dir), 'directory does not exist: ' .. self.dir)
end

function ImagenetDataset:get(i)
    local path = ffi.string(self.imageInfo.imagePath[i]:data())

    local image = self:_loadImage(paths.concat(self.dir, path))
    local class = self.imageInfo.imageClass[i]

    return {
        input = image,
        target = class,
    }
end

function ImagenetDataset:_loadImage(path)
    local ok, input = pcall(function()
            -- convert RGB to BGR
            return image.load(path, 3, 'float'):index(1, self.perm):mul(255.0)
        end)

    -- Sometimes image.load fails because the file extension does not match the
    -- image format. In that case, use image.decompress on a ByteTensor.
    if not ok then
        local f = io.open(path, 'r')
        assert(f, 'Error reading: ' .. tostring(path))
        local data = f:read('*a')
        f:close()

        local b = torch.ByteTensor(string.len(data))
        ffi.copy(b:data(), data, b:size(1))

        input = image.decompress(b, 3, 'float')
    end

    return input
end

function ImagenetDataset:size()
    return self.imageInfo.imageClass:size(1)
end

-- Computed from random subset of ImageNet training images
--[[local meanstd = {
mean = { 0.485, 0.456, 0.406 },
std = { 0.229, 0.224, 0.225 },
}]]--


local pca = {
    eigval = torch.Tensor{ 0.2175, 0.0188, 0.0045 },
    eigvec = torch.Tensor{
        { -0.5675,  0.7192,  0.4009 },
        { -0.5808, -0.0045, -0.8140 },
        { -0.5836, -0.6948,  0.4203 },
    },
}

function ImagenetDataset:preprocess()
    if self.split == 'train' then
        if self.opt.externalMeanFile then
            return t.Compose{
                t.RandomSizedCrop(224),
                t.ColorJitter({
                        brightness = 0.4,
                        contrast = 0.4,
                        saturation = 0.4,
                    }),
                t.Lighting(0.1, pca.eigval, pca.eigvec),
                t.SubstractMean(self.meanstd),
                t.HorizontalFlip(0.5),
            }
        else
            return t.Compose{
                t.RandomSizedCrop(224),
                t.ColorJitter({
                        brightness = 0.4,
                        contrast = 0.4,
                        saturation = 0.4,
                    }),
                t.Lighting(0.1, pca.eigval, pca.eigvec),
                t.ColorNormalize(self.meanstd),
                t.HorizontalFlip(0.5),
            }
        end
    elseif self.split == 'val' then
        local Crop = self.opt.tenCrop and t.TenCrop or t.CenterCrop
        if self.opt.externalMeanFile then
            return t.Compose{
                t.Scale(256),
                t.SubstractMean(self.meanstd),
                Crop(224),
            }
        else
            return t.Compose{
                t.Scale(256),
                t.ColorNormalize(self.meanstd),
                Crop(224),
            }
        end
    else
        error('invalid split: ' .. self.split)
    end
end

return M.ImagenetDataset